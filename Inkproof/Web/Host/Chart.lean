/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Support
import Lasm.JS.Web.Fetch
import Std.Data.HashMap
import Inkproof.Viewport.Gesture
import Inkproof.Web.Surface
import Inkproof.Web.Frame
import Inkproof.Web.Attr
import Inkproof.Web.Access
import Inkproof.Web.Pointer
import Inkproof.Web.Host.Console
import Inkproof.Web.Host.Gpu
import Inkproof.Web.Host.Element

namespace Inkproof.Web.Host
open Lasm.JS Inkproof.Viewport

/-- Which side of its anchor a label's text lies on along the baseline. -/
inductive Align where
  | start
  | center
  | «end»

/-- Where a label's anchor lies against the height of its text. -/
inductive Baseline where
  | top
  | middle
  | alphabetic
  | bottom

/-- The Canvas 2D `textAlign` value. -/
def Align.canvas : Align → String
  | .start => "start"
  | .center => "center"
  | .end => "end"

/-- The Canvas 2D `textBaseline` value. -/
def Baseline.canvas : Baseline → String
  | .top => "top"
  | .middle => "middle"
  | .alphabetic => "alphabetic"
  | .bottom => "bottom"

theorem Align.canvas_eq (a : Align) : a.canvas =
    match a with
    | .start => "start"
    | .center => "center"
    | .end => "end" := by
  cases a <;> rfl

theorem Baseline.canvas_eq (b : Baseline) : b.canvas =
    match b with
    | .top => "top"
    | .middle => "middle"
    | .alphabetic => "alphabetic"
    | .bottom => "bottom" := by
  cases b <;> rfl

theorem Align.canvas_injective: Function.Injective Align.canvas := by
  intro a b h
  cases a <;> cases b <;> first | rfl | (simp [Align.canvas] at h)

theorem Baseline.canvas_injective : Function.Injective Baseline.canvas := by
  intro a b h
  cases a <;> cases b <;> first | rfl | (simp [Baseline.canvas] at h)

/-- A piece of text for the Canvas 2D layer, anchored at `x`, `y` in CSS pixels from the chart's top left. The text is turned about the anchor by `rotation` radians, clockwise on the page. -/
structure Label where
  text : String
  x : Float
  y : Float
  align : Align := .start
  baseline : Baseline := .alphabetic
  rotation : Float := 0
  font : String := "12px sans-serif"
  color : String := "#000"

/-- What a chart shows: the encoded Gpu command list for the data layers, and the text over them. -/
structure Scene where
  commands : ByteArray
  labels : Array Label := #[]
  access : Access := {}

/-- Fetch `src` and take its body as the command list. -/
def fetchScene (src : String) : Async Scene := do
  let response ← Web.fetch (.usvString src)
  unless (← response.ok) do
    throw (IO.userError s!"fetching {src} gave status {← response.status}")
  return { commands := ← response.bytes }

private structure Shared where
  canvas : Value
  gl : Value
  state : IO.Ref Value

private structure Chart where
  id : Nat
  el : Value
  canvas : Value
  ctx : Value
  announcer : Value
  table : Value
  nav : IO.Ref (Option Nav)
  listeners : IO.Ref (Array (String × Value))
  pointers : IO.Ref (Array (Nat × Px))
  boxStart : IO.Ref (Option Px)
  frame : IO.Ref Frame
  scheduled : IO.Ref Bool
  alive : IO.Ref Bool
  size : IO.Ref Size
  ratio : IO.Ref Milli
  scene : IO.Ref (Option Scene)
  generation : IO.Ref Nat
  frameCallback : IO.Ref (Option Value)
  observer : IO.Ref (Option Value)
  ratioQuery : IO.Ref (Option (Value × Value))

/-- One WebGL2 context serves every chart on the page: each draws into it and copies the result to its own canvas. -/
initialize shared : IO.Ref (Option (Option Shared)) ← IO.mkRef none
initialize contextLost : IO.Ref Bool ← IO.mkRef false
initialize generation : IO.Ref Nat ← IO.mkRef 0
initialize live : IO.Ref (Std.HashMap Nat Chart) ← IO.mkRef {}
initialize nextId : IO.Ref Nat ← IO.mkRef 0
/-- Redraws every chart; set once `schedule` exists, since drawing is what creates the context that reports its restoration. -/
initialize redrawAll : IO.Ref (IO Unit) ← IO.mkRef (pure ())

/-- How many times the shared context has been lost and restored. A list that draws buffers or programs an earlier list uploaded is valid only while this is the value it was built under; after a change, build the next list as for a fresh context. -/
def contextGeneration : IO Nat := generation.get

private def idKey : String := "__inkproofChart"

private def dispatch (el : Value) (name : String) (detail : Data) : IO Unit := do
  let ctor ← (← global).get "CustomEvent"
  let event ← ctor.new #[toJS name, obj [("bubbles", .bool true), ("composed", .bool true), ("detail", detail)]]
  discard <| el.callMethod "dispatchEvent" #[toJS event] Bool

private def fail (c : Chart) (message : String) (values : List (String × String)) : IO Unit := do
  log .warn message values
  dispatch c.el "inkproof-error" (obj [("message", .string message)])

private def sharedContext (c : Chart) : IO (Option Shared) := do
  if let some s ← shared.get then return s
  let canvas ← (← (← global).get "document").callMethod "createElement" #[toJS "canvas"]
  let gl ← Web.Support.optionalValue (← canvas.callMethod "getContext" #[toJS "webgl2"] Data)
  let s ← match gl with
    | some gl => do pure (some { canvas, gl, state := ← IO.mkRef (← newState) : Shared })
    | none => pure none
  shared.set (some s)
  if let some s := s then
    let lost ← Function.ofSyncFn fun args => do
      if let some (Data.ref e _) := args[0]? then discard <| e.callMethod "preventDefault" #[] Unit
      contextLost.set true
      -- The context's objects are gone with it, so the interpreter's tables must not name them.
      s.state.set (← newState)
      generation.modify (· + 1)
      log .warn "WebGL context lost, waiting for restoration" []
      return .undefined
    let restored ← Function.ofSyncFn fun _ => do
      contextLost.set false
      log .warn "WebGL context restored, redrawing" [("charts", toString (← live.get).size)]
      let gen ← generation.get
      for (_, chart) in (← live.get) do
        dispatch chart.el "inkproof-contextrestored" (obj [("generation", toJS gen)])
      (← redrawAll.get)
      return .undefined
    s.canvas.callMethod "addEventListener" #[toJS "webglcontextlost", toJS lost] Unit
    s.canvas.callMethod "addEventListener" #[toJS "webglcontextrestored", toJS restored] Unit
    log .debug "created the shared WebGL2 context" []
  else
    fail c "WebGL2 is unavailable, data layers cannot be drawn" []
  return s

private def getAttr (el : Value) (name : String) : IO (Option String) := do
  match ← el.callMethod "getAttribute" #[toJS name] Data with
  | .string s => return some s
  | _ => return none

private def draw (c : Chart) : IO Unit := do
  let size ← c.size.get
  let some scene ← c.scene.get | return
  if size.width == 0 || size.height == 0 then return
  let ratio ← c.ratio.get
  if let some s ← sharedContext c then
    if ← contextLost.get then
      log .info "draw skipped, WebGL context lost" []
      return
    if (← s.canvas.get "width" Nat) != size.width then s.canvas.set "width" size.width
    if (← s.canvas.get "height" Nat) != size.height then s.canvas.set "height" size.height
    s.gl.callMethod "viewport" #[toJS 0, toJS 0, toJS size.width, toJS size.height] Unit
    run s.gl (← s.state.get) scene.commands
    c.ctx.callMethod "setTransform" #[toJS 1, toJS 0, toJS 0, toJS 1, toJS 0, toJS 0] Unit
    c.ctx.callMethod "clearRect" #[toJS 0, toJS 0, toJS size.width, toJS size.height] Unit
    c.ctx.callMethod "drawImage" #[toJS s.canvas, toJS 0, toJS 0] Unit
  else
    c.ctx.callMethod "setTransform" #[toJS 1, toJS 0, toJS 0, toJS 1, toJS 0, toJS 0] Unit
    c.ctx.callMethod "clearRect" #[toJS 0, toJS 0, toJS size.width, toJS size.height] Unit
  let scale := ratio.toFloat / 1000
  c.ctx.callMethod "setTransform" #[toJS scale, toJS 0, toJS 0, toJS scale, toJS 0, toJS 0] Unit
  for label in scene.labels do
    c.ctx.set "font" label.font
    c.ctx.set "fillStyle" label.color
    c.ctx.set "textAlign" label.align.canvas
    c.ctx.set "textBaseline" label.baseline.canvas
    c.ctx.callMethod "save" #[] Unit
    c.ctx.callMethod "translate" #[toJS label.x, toJS label.y] Unit
    c.ctx.callMethod "rotate" #[toJS label.rotation] Unit
    c.ctx.callMethod "fillText" #[toJS label.text, toJS 0, toJS 0] Unit
    c.ctx.callMethod "restore" #[] Unit
  dispatch c.el "inkproof-draw" (obj [("width", toJS size.width), ("height", toJS size.height)])

private def onFrame (c : Chart) : IO Unit := do
  c.scheduled.set false
  if (← c.alive.get) && (← c.frame.get).shouldDraw then
    draw c
    c.frame.modify Frame.drawn

/-- Ask for a frame, unless one is already coming; with nothing invalidated nothing is scheduled, so an idle chart costs nothing. -/
private def schedule (c : Chart) : IO Unit := do
  if (← c.scheduled.get) then return
  c.scheduled.set true
  let some callback ← c.frameCallback.get | return
  discard <| (← global).callMethod "requestAnimationFrame" #[toJS callback] Nat

private def invalidate (c : Chart) : IO Unit := do
  c.frame.modify Frame.invalidate
  schedule c

private def sync (c : Chart) : IO Unit := do
  let rect ← c.el.callMethod "getBoundingClientRect" #[]
  let width ← rect.get "width" Float
  let height ← rect.get "height" Float
  let dpr ← (← global).get "devicePixelRatio" Float
  let ratio : Milli := (dpr * 1000).round.toUInt64.toNat
  let cssWidth := width.round.toUInt64.toNat
  let cssHeight := height.round.toUInt64.toNat
  let current ← c.size.get
  if current.needsResize cssWidth cssHeight ratio then
    let next := Size.backing cssWidth cssHeight ratio
    c.canvas.set "width" next.width
    c.canvas.set "height" next.height
    c.size.set next
    c.ratio.set ratio
    log .debug "chart resized" [("css", s!"{cssWidth}x{cssHeight}"), ("ratio", toString ratio), ("backing", s!"{next.width}x{next.height}")]
    invalidate c

/-- A change in device pixel ratio fires no resize, but it flips the media query that names the old ratio. Partial because the listener, which fires once, re-arms itself and so recurses through a closure. -/
private partial def watchRatio (c : Chart) : IO Unit := do
  let dpr ← (← global).get "devicePixelRatio" Float
  let query ← (← global).callMethod "matchMedia" #[toJS s!"(resolution: {dpr}dppx)"]
  let changed ← Function.ofSyncFn fun _ => do
    if (← c.alive.get) then
      sync c
      watchRatio c
    return .undefined
  query.callMethod "addEventListener" #[toJS "change", toJS changed, obj [("once", .bool true)]] Unit
  c.ratioQuery.set (some (query, changed))

private def styles : String :=
  ":host{display:block;width:300px;height:150px}canvas{display:block;width:100%;height:100%}:host{touch-action:none}" ++
  ".hidden{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}" ++
  ":host([show-table]) canvas{display:none}:host([show-table]) .hidden:not([aria-live]){position:static;width:100%;height:auto;overflow:auto;clip-path:none}"

private def newElement (doc : Value) (tag : String) : IO Value := doc.callMethod "createElement" #[toJS tag]

private def build (id : Nat) (el : Value) : IO Chart := do
  let doc ← (← global).get "document"
  let root ← match ← Web.Support.optionalValue (← el.get "shadowRoot" Data) with
    | some root => pure root
    | none =>
      let root ← el.callMethod "attachShadow" #[obj [("mode", .string "open")]]
      let style ← doc.callMethod "createElement" #[toJS "style"]
      style.set "textContent" styles
      root.callMethod "append" #[toJS style] Unit
      root.callMethod "append" #[toJS (← newElement doc "canvas")] Unit
      let announcer ← newElement doc "div"
      announcer.callMethod "setAttribute" #[toJS "aria-live", toJS "polite"] Unit
      announcer.set "className" "hidden"
      let table ← newElement doc "table"
      let wrapper ← newElement doc "div"
      wrapper.set "className" "hidden"
      wrapper.callMethod "append" #[toJS table] Unit
      root.callMethod "append" #[toJS announcer, toJS wrapper] Unit
      pure root
  let canvas ← root.callMethod "querySelector" #[toJS "canvas"]
  let announcer ← root.callMethod "querySelector" #[toJS "div"]
  let table ← root.callMethod "querySelector" #[toJS "table"]
  let ctx ← canvas.callMethod "getContext" #[toJS "2d"]
  return {
    id, el, canvas, ctx, announcer, table
    nav := ← IO.mkRef none, listeners := ← IO.mkRef #[], pointers := ← IO.mkRef #[], boxStart := ← IO.mkRef none
    frame := ← IO.mkRef Frame.initial, scheduled := ← IO.mkRef false, alive := ← IO.mkRef true
    size := ← IO.mkRef ⟨0, 0⟩, ratio := ← IO.mkRef 1000, scene := ← IO.mkRef none
    generation := ← IO.mkRef 0, frameCallback := ← IO.mkRef none, observer := ← IO.mkRef none
    ratioQuery := ← IO.mkRef none }

private def setText (c : Chart) (text : String) : IO Unit := c.announcer.set "textContent" text

private def refreshSummary (c : Chart) (access : Access) : IO Unit := do
  let view := (← c.nav.get).map (·.view)
  c.el.callMethod "setAttribute" #[toJS "aria-description", toJS (access.summaryText view)] Unit

private def rebuildTable (c : Chart) (access : Access) : IO Unit := do
  let doc ← (← global).get "document"
  c.table.callMethod "replaceChildren" #[] Unit
  let row (cells : Array String) (tag : String) : IO Unit := do
    let tr ← newElement doc "tr"
    for cell in cells do
      let td ← newElement doc tag
      td.set "textContent" cell
      tr.callMethod "append" #[toJS td] Unit
    c.table.callMethod "append" #[toJS tr] Unit
  unless access.header.isEmpty do row access.header "th"
  for cells in access.rows do row cells "td"

private def describe (c : Chart) (access : Access) : IO Unit := do
  if (← getAttr c.el "tabindex").isNone then c.el.callMethod "setAttribute" #[toJS "tabindex", toJS "0"] Unit
  c.el.callMethod "setAttribute" #[toJS "role", toJS "img"] Unit
  c.el.callMethod "setAttribute" #[toJS "aria-label", toJS access.name] Unit
  refreshSummary c access
  rebuildTable c access

/-- Make the chart reachable by keyboard and assistive technology: focusable, named, described, with the data as a table. -/
private def publish (c : Chart) (access : Access) : IO Unit := do
  c.nav.set (access.view.map fun v => Nav.home ⟨v, access.points, access.series.size⟩)
  describe c access

/-- Make `next` the chart's state, telling the application and assistive technology of what changed from `nav`. -/
private def commit (c : Chart) (scene : Scene) (nav next : Nav) : IO Unit := do
  c.nav.set (some next)
  if next.view != nav.view then
    let x := next.view.x
    let y := next.view.y
    dispatch c.el "inkproof-view" (obj [("xStart", toJS x.start), ("xEnd", toJS (x.start + x.span)),
      ("yStart", toJS y.start), ("yEnd", toJS (y.start + y.span))])
    refreshSummary c scene.access
    setText c (scene.access.summaryText (some next.view))
  if next.point != nav.point || next.series != nav.series then
    dispatch c.el "inkproof-cursor" (obj [("series", toJS next.series), ("point", toJS next.point)])
    setText c (scene.access.cursorText next)

private def navigable (c : Chart) : IO (Option (Scene × NavConfig × Nav)) := do
  let some scene ← c.scene.get | return none
  let some config := scene.access.view | return none
  let some nav ← c.nav.get | return none
  return some (scene, ⟨config, scene.access.points, scene.access.series.size⟩, nav)

private def onKey (c : Chart) (event : Value) : IO Unit := do
  let some (scene, navConfig, nav) ← navigable c | return
  let held (flag : String) : IO Bool := event.get flag Bool
  if (← held "ctrlKey") || (← held "altKey") || (← held "metaKey") then return
  let key ← event.get "key" String
  let some command := Command.ofKey key (← held "shiftKey") | return
  event.callMethod "preventDefault" #[] Unit
  commit c scene nav (nav.apply navConfig command)

private def position (c : Chart) (event : Value) : IO Px := do
  let rect ← c.el.callMethod "getBoundingClientRect" #[]
  return ((← event.get "clientX" Float) - (← rect.get "left" Float),
          (← event.get "clientY" Float) - (← rect.get "top" Float))

private def applyInputs (c : Chart) (inputs : List (Input Float)) : IO Unit := do
  let some (scene, navConfig, nav) ← navigable c | return
  commit c scene nav (inputs.foldl (·.input navConfig ·) nav)

private def onWheel (c : Chart) (event : Value) : IO Unit := do
  let some (_, navConfig, _) ← navigable c | return
  event.callMethod "preventDefault" #[] Unit
  let scale : Float := if (← event.get "deltaMode" Nat) == 1 then 16 else 1
  let p := Gesture.toView navConfig.view (← position c event)
  let factor := Gesture.wheelFactor (scale * (← event.get "deltaY" Float))
  applyInputs c [.wheel p.1 p.2 factor]

private def onPointerDown (c : Chart) (event : Value) : IO Unit := do
  let some _ ← navigable c | return
  let id ← event.get "pointerId" Nat
  let p ← position c event
  c.pointers.modify (·.filter (·.1 != id) |>.push (id, p))
  -- A pointer the browser no longer considers active cannot be captured; the gesture still works.
  try c.el.callMethod "setPointerCapture" #[toJS id] Unit
  catch e => log .warn "pointer capture failed, continuing without it" [("error", toString e)]
  c.boxStart.set (if (← c.pointers.get).size == 1 && (← event.get "shiftKey" Bool) then some p else none)

private def onPointerMove (c : Chart) (event : Value) : IO Unit := do
  let some (_, navConfig, nav) ← navigable c | return
  let id ← event.get "pointerId" Nat
  let p ← position c event
  let tracked ← c.pointers.get
  if tracked.any (·.1 == id) then
    let toView := Gesture.toView navConfig.view
    let moved := tracked.map fun t => if t.1 == id then (id, p) else t
    c.pointers.set moved
    match tracked, moved with
    | #[(_, o₁), (_, o₂)], #[(_, n₁), (_, n₂)] =>
      applyInputs c (Gesture.pinch (toView o₁) (toView o₂) (toView n₁) (toView n₂))
    | #[(_, old)], _ =>
      if (← c.boxStart.get).isNone then
        let o := toView old
        let n := toView p
        applyInputs c [.drag (n.1 - o.1) (n.2 - o.2)]
    | _, _ => pure ()
  if Gesture.inside navConfig.view p then
    let v := Gesture.toView navConfig.view p
    let d := View.cursor navConfig.view ((← c.nav.get).getD nav).view v.1 v.2
    dispatch c.el "inkproof-pointer" (obj [("x", toJS d.1), ("y", toJS d.2)])

private def onPointerUp (c : Chart) (event : Value) : IO Unit := do
  let id ← event.get "pointerId" Nat
  if let some start ← c.boxStart.get then
    c.boxStart.set none
    if (← event.get "type" String) == "pointerup" then
      if let some (_, navConfig, _) ← navigable c then
        if let some input := Gesture.box navConfig.view start (← position c event) then applyInputs c [input]
  c.pointers.modify (·.filter (·.1 != id))

private def load (c : Chart) (loader : String → Async Scene) : Async Unit := do
  let src ← getAttr c.el "src"
  let level ← getAttr c.el "log-level"
  match ChartAttrs.parse src level with
  | .error message => fail c message []
  | .ok attrs =>
    if let some l := attrs.logLevel then setThreshold l
    c.generation.modify (· + 1)
    let generation ← c.generation.get
    try
      let scene ← loader attrs.src
      -- A newer load or a disconnect has overtaken this one.
      if (← c.generation.get) == generation && (← c.alive.get) then
        c.scene.set (some scene)
        publish c scene.access
        invalidate c
    catch e =>
      fail c s!"loading the chart failed: {e}" [("src", attrs.src)]

private def chartOfElement (el : Value) : IO (Option Chart) := do
  match ← el.get idKey Data with
  | .number id => return (← live.get)[id.toUInt64.toNat]?
  | _ => return none

/-- Replace the chart's scene, keeping its view, cursor and series (the cursor moved inside the new scene's data), and draw it; buffers already on the GPU are not uploaded again. A scene with no view configuration leaves the chart not navigable. -/
def setScene (el : Value) (scene : Scene) : IO Unit := do
  let some c ← chartOfElement el | return
  unless (← c.alive.get) do return
  let kept := (← c.nav.get).map (Nav.clamp scene.access.points scene.access.series.size)
  c.scene.set (some scene)
  c.nav.set (match scene.access.view, kept with
    | some _, some nav => some nav
    | some v, none => some (Nav.home ⟨v, scene.access.points, scene.access.series.size⟩)
    | none, _ => none)
  describe c scene.access
  invalidate c

/-- Apply `command` to the chart as the key for it would, telling the application of what changed. -/
def apply (el : Value) (command : Command) : IO Unit := do
  let some c ← chartOfElement el | return
  let some (scene, navConfig, nav) ← navigable c | return
  commit c scene nav (nav.apply navConfig command)

private def chartOf (args : Array Data) : IO (Option Chart) := do
  let some (Data.ref el _) := args[0]? | return none
  chartOfElement el

private def connect (loader : String → Async Scene) (args : Array Data) : Async Unit := do
  let some (Data.ref el _) := args[0]? | return
  let id ← nextId.modifyGet fun n => (n, n + 1)
  let c ← build id el
  el.set idKey id
  live.modify (·.insert id c)
  for (name, handler) in [("keydown", onKey c), ("wheel", onWheel c), ("pointerdown", onPointerDown c),
      ("pointermove", onPointerMove c), ("pointerup", onPointerUp c), ("pointercancel", onPointerUp c)] do
    let listener ← Function.ofSyncFn fun args => do
      if let some (Data.ref event _) := args[0]? then handler event
      return .undefined
    let options := if name == "wheel" then obj [("passive", .bool false)] else obj []
    el.callMethod "addEventListener" #[toJS name, toJS listener, options] Unit
    c.listeners.modify (·.push (name, listener))
  c.frameCallback.set (some (← Function.ofSyncFn fun _ => do onFrame c; return .undefined))
  let observe ← Function.ofSyncFn fun _ => do
    if (← c.alive.get) then sync c
    return .undefined
  let observer ← (← (← global).get "ResizeObserver").new #[toJS observe]
  observer.callMethod "observe" #[toJS el] Unit
  c.observer.set (some observer)
  watchRatio c
  sync c
  load c loader

private def disconnect (args : Array Data) : IO Data := do
  if let some c ← chartOf args then
    c.alive.set false
    for (name, listener) in ← c.listeners.get do
      c.el.callMethod "removeEventListener" #[toJS name, toJS listener] Unit
    if let some o ← c.observer.get then o.callMethod "disconnect" #[] Unit
    if let some (query, changed) ← c.ratioQuery.get then
      query.callMethod "removeEventListener" #[toJS "change", toJS changed] Unit
    live.modify (·.erase c.id)
    if (← live.get).isEmpty then
      if let some (some s) ← shared.get then
        releaseState s.gl (← s.state.get)
        s.state.set (← newState)
        generation.modify (· + 1)
  return .undefined

private def changed (loader : String → Async Scene) (args : Array Data) : Async Unit := do
  if let some c ← chartOf args then
    if (← c.alive.get) then load c loader

/-- Define the custom element `tag`: it draws the scene `loader` makes of its `src` attribute. -/
def register (tag : String) (loader : String → Async Scene := fetchScene) : IO Unit := do
  redrawAll.set do
    for (_, chart) in (← live.get) do invalidate chart
  defineElement tag #["src", "log-level"]
    (← Function.ofFn (connect loader · *> pure .undefined))
    (← Function.ofSyncFn disconnect)
    (← Function.ofFn (changed loader · *> pure .undefined))

end Inkproof.Web.Host
