/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Support
import Lasm.JS.Web.Fetch
import Std.Data.HashMap
import Inkproof.Viewport.Gesture
import Inkproof.Viewport.Linked
import Inkproof.Web.Surface
import Inkproof.Web.Host.Measure
import Inkproof.Web.Frame
import Inkproof.Web.Attr
import Inkproof.Web.Access
import Inkproof.Web.Pointer
import Inkproof.Web.Box
import Inkproof.Web.Cursor
import Inkproof.Web.Legend
import Inkproof.Web.Markers
import Inkproof.Web.CursorStyle
import Inkproof.Web.Interaction
import Inkproof.Web.Tooltip
import Inkproof.Web.Numbers
import Inkproof.Web.Group
import Inkproof.Web.Input
import Inkproof.Web.Select
import Inkproof.Web.Events
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

/-- A piece of text for the Canvas 2D layer, anchored at `x`, `y` in CSS pixels from the chart's top left. The text is turned about the anchor by `rotation` radians, clockwise on the page. `second`, if any, is a second line under the first, with the same anchor, alignment and rotation, one measured line height lower. -/
structure Label where
  text : String
  x : Float
  y : Float
  align : Align := .start
  baseline : Baseline := .alphabetic
  rotation : Float := 0
  font : String := "12px sans-serif"
  color : String := "#000"
  second : Option String := none

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

/-- Makes the scene for a `src`, the CSS size of the chart's canvas and its backing store size in device pixels. -/
private abbrev Loader := String → Nat × Nat → Nat × Nat → Async Scene

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
  tip : Value
  legendEl : Value
  titleEl : Value
  nav : IO.Ref (Option Nav)
  listeners : IO.Ref (Array (String × Value))
  pointers : IO.Ref (Array (Nat × Px))
  boxStart : IO.Ref (Option Px)
  boxConfig : IO.Ref BoxConfig
  group : IO.Ref (Option String)
  dragMode : IO.Ref DragMode
  wheelMode : IO.Ref WheelMode
  touchMode : IO.Ref TouchMode
  cursorMode : IO.Ref CursorMode
  cursorDotted : IO.Ref Bool
  markerMode : IO.Ref MarkerMode
  markerStyle : IO.Ref MarkerStyle
  tooltipStyle : IO.Ref (Option Tooltip.Style)
  numberFormat : IO.Ref (Option Inkproof.Axis.NumberFormat)
  /-- The legend's style, none when it shows no legend. -/
  legendStyle : IO.Ref (Option Legend.Style)
  /-- Which series the legend has hidden, by index. -/
  hidden : IO.Ref (Array Bool)
  /-- Which hideable value groups the legend has hidden, by index. -/
  hiddenGroups : IO.Ref (Array Bool)
  selectMode : IO.Ref SelectMode
  /-- The selected x range, in data coordinates. -/
  band : IO.Ref (Option (Selection.Band Float))
  selectDrag : IO.Ref (Option (Selection.Drag Float))
  /-- The data position of the cursor, with the y position when the pointer is over this chart. -/
  cursor : IO.Ref (Option (Float × Option Float))
  frame : IO.Ref Frame
  scheduled : IO.Ref Bool
  alive : IO.Ref Bool
  size : IO.Ref Size
  ratio : IO.Ref Milli
  scene : IO.Ref (Option Scene)
  generation : IO.Ref Nat
  frameCallback : IO.Ref (Option Value)
  observer : IO.Ref (Option Value)
  /-- The CSS size the scene was last made for. -/
  sceneSize : IO.Ref ((Nat × Nat) × (Nat × Nat))
  /-- Counts size changes, so that only the last of a burst reloads the scene. -/
  resizes : IO.Ref Nat
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

/-- The scene's traces with the legend's choice of which are hidden. -/
private def activeTraces (c : Chart) (scene : Scene) : IO (Array Trace) := do
  let mask ← c.hidden.get
  return scene.access.traces.mapIdx fun i t => { t with hidden := mask[i]?.getD t.hidden }

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
    if let some second := label.second then
      let (_, lineHeight) := (← measurer label.font #[second]) second
      if lineHeight.isFinite then
        c.ctx.callMethod "fillText" #[toJS second, toJS 0, toJS lineHeight] Unit
    c.ctx.callMethod "restore" #[] Unit
  if let (some band, some config) := (← c.band.get, scene.access.view) then
    let view := ((← c.nav.get).map (·.view)).getD (View.home config)
    let (left, right) := Select.extent config view band
    let origin := scene.access.plotOrigin
    c.ctx.set "fillStyle" "rgba(0, 100, 255, 0.2)"
    c.ctx.callMethod "fillRect" #[toJS (origin.1 + left), toJS origin.2, toJS (right - left), toJS config.y.length] Unit
    c.ctx.set "strokeStyle" "rgba(0, 100, 255, 0.8)"
    c.ctx.set "lineWidth" 1
    c.ctx.callMethod "strokeRect" #[toJS (origin.1 + left), toJS origin.2, toJS (right - left), toJS config.y.length] Unit
  if let (some (x, y), some config) := (← c.cursor.get, scene.access.view) then
    let view := ((← c.nav.get).map (·.view)).getD (View.home config)
    c.ctx.set "strokeStyle" "rgba(0, 0, 0, 0.5)"
    c.ctx.set "lineWidth" 1
    c.ctx.callMethod "setLineDash" #[toJS (if (← c.cursorDotted.get) then #[(2 : Float), 3] else #[])] Unit
    let origin := scene.access.plotOrigin
    for l in Cursor.lines (← c.cursorMode.get) config view x y do
      c.ctx.callMethod "beginPath" #[] Unit
      c.ctx.callMethod "moveTo" #[toJS (origin.1 + l.x₁), toJS (origin.2 + l.y₁)] Unit
      c.ctx.callMethod "lineTo" #[toJS (origin.1 + l.x₂), toJS (origin.2 + l.y₂)] Unit
      c.ctx.callMethod "stroke" #[] Unit
    c.ctx.callMethod "setLineDash" #[toJS (#[] : Array Float)] Unit
    let style ← c.markerStyle.get
    for m in Markers.atCursor (← c.markerMode.get) style config view (← activeTraces c scene) x y do
      c.ctx.callMethod "beginPath" #[] Unit
      c.ctx.callMethod "arc" #[toJS (origin.1 + m.x), toJS (origin.2 + m.y), toJS (style.size / 2), toJS 0, toJS (2 * 3.141592653589793 : Float)] Unit
      if m.filled then
        c.ctx.set "fillStyle" m.color
        c.ctx.callMethod "fill" #[] Unit
      else
        c.ctx.set "strokeStyle" m.color
        c.ctx.set "lineWidth" 2
        c.ctx.callMethod "stroke" #[] Unit
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

/-- The canvas's size in CSS pixels, which is the element's less the room a legend outside the plot takes. -/
private def cssSize (c : Chart) : IO (Nat × Nat) := do
  let rect ← c.canvas.callMethod "getBoundingClientRect" #[]
  let width ← rect.get "width" Float
  let height ← rect.get "height" Float
  return (width.round.toUInt64.toNat, height.round.toUInt64.toNat)

private def devicePixelRatio : IO Milli := do
  let dpr ← (← global).get "devicePixelRatio" Float
  return (dpr * 1000).round.toUInt64.toNat

/-- The canvas's CSS size and the backing store size it needs at the current device pixel ratio. -/
private def sceneSizes (c : Chart) : IO ((Nat × Nat) × (Nat × Nat)) := do
  let (w, h) ← cssSize c
  let b := Size.backing w h (← devicePixelRatio)
  return ((w, h), (b.width, b.height))

private def sync (c : Chart) : IO Unit := do
  let (cssWidth, cssHeight) ← cssSize c
  let ratio ← devicePixelRatio
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
private partial def watchRatio (c : Chart) (after : IO Unit) : IO Unit := do
  let dpr ← (← global).get "devicePixelRatio" Float
  let query ← (← global).callMethod "matchMedia" #[toJS s!"(resolution: {dpr}dppx)"]
  let changed ← Function.ofSyncFn fun _ => do
    if (← c.alive.get) then
      sync c
      after
      watchRatio c after
    return .undefined
  query.callMethod "addEventListener" #[toJS "change", toJS changed, obj [("once", .bool true)]] Unit
  c.ratioQuery.set (some (query, changed))

private def styles : String :=
  ":host{display:block;width:300px;height:150px}canvas{display:block;width:100%;height:100%}:host([data-touch-action=none]){touch-action:none}:host([data-touch-action=pan-y]){touch-action:pan-y}:host([data-touch-action=pan-xy]){touch-action:pan-x pan-y}" ++
  ":host{position:relative}.tip{position:absolute;display:none;pointer-events:none;white-space:pre;box-sizing:border-box;padding:var(--inkproof-tooltip-padding,2px 6px);color:var(--inkproof-tooltip-color,inherit);background:var(--inkproof-tooltip-background,#fff);border:var(--inkproof-tooltip-border-width,1px) solid var(--inkproof-tooltip-border-color,#888);border-radius:var(--inkproof-tooltip-border-radius,0);box-shadow:var(--inkproof-tooltip-shadow,none);font:var(--inkproof-tooltip-font-size,12px) var(--inkproof-tooltip-font-family,sans-serif)}" ++
  ".legend{position:absolute;top:0;right:0;display:flex;color:var(--inkproof-legend-color,inherit);font:var(--inkproof-legend-font-size,12px) var(--inkproof-legend-font-family,sans-serif)}.legend button,.legend .entry{display:flex;gap:4px;align-items:center;border:0;background:none;font:inherit}.legend button{cursor:pointer;color:var(--inkproof-legend-color,buttontext)}" ++
  ".legend[data-layout=vertical]{flex-direction:column}.legend[data-layout=horizontal]{flex-direction:row;flex-wrap:wrap;align-items:center;gap:0 12px;max-width:100%}" ++
  ".legend[data-place=top-left]{top:0;right:auto;left:0}.legend[data-place=bottom-left]{top:auto;right:auto;bottom:0;left:0}.legend[data-place=bottom-right]{top:auto;bottom:0;right:0}" ++
  ":host([data-legend-below]),:host([data-title]){display:flex;flex-direction:column}:host([data-legend-below]) canvas,:host([data-title]) canvas{flex:1 1 0;min-height:0;height:auto}" ++
  ".title{display:none;flex:none;text-align:center;color:var(--inkproof-title-color,inherit);font:var(--inkproof-title-font-size,16px) var(--inkproof-title-font-family,sans-serif);padding:var(--inkproof-title-padding,4px 0)}:host([data-title]) .title{display:block}" ++
  ".legend[data-place^=below]{position:static;flex:none;min-height:20px}" ++
  ".legend[data-layout=horizontal][data-place=below-left]{justify-content:flex-start}.legend[data-layout=horizontal][data-place=below-center]{justify-content:center}.legend[data-layout=horizontal][data-place=below-right]{justify-content:flex-end}" ++
  ".legend[data-layout=vertical][data-place=below-left]{align-items:flex-start}.legend[data-layout=vertical][data-place=below-center]{align-items:center}.legend[data-layout=vertical][data-place=below-right]{align-items:flex-end}" ++
  ".legend .readout{text-align:right}.legend[data-place$=left] .readout{text-align:left}.legend button[aria-pressed=false]{opacity:0.4}.swatch{display:inline-block;width:10px;height:10px}" ++
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
  for old in ["tip", "legend", "title"] do
    if let some e ← Web.Support.optionalValue (← root.callMethod "querySelector" #[toJS s!".{old}"] Data) then
      e.callMethod "remove" #[] Unit
  let tip ← newElement doc "div"
  tip.set "className" "tip"
  tip.callMethod "setAttribute" #[toJS "part", toJS "tooltip"] Unit
  let legendEl ← newElement doc "div"
  legendEl.set "className" "legend"
  root.callMethod "append" #[toJS tip, toJS legendEl] Unit
  let canvas ← root.callMethod "querySelector" #[toJS "canvas"]
  let titleEl ← newElement doc "div"
  titleEl.set "className" "title"
  titleEl.callMethod "setAttribute" #[toJS "part", toJS "title"] Unit
  canvas.callMethod "before" #[toJS titleEl] Unit
  let announcer ← root.callMethod "querySelector" #[toJS "[aria-live]"]
  let table ← root.callMethod "querySelector" #[toJS "table"]
  let ctx ← canvas.callMethod "getContext" #[toJS "2d"]
  return {
    id, el, canvas, ctx, announcer, table, tip, legendEl, titleEl
    nav := ← IO.mkRef none, listeners := ← IO.mkRef #[], pointers := ← IO.mkRef #[], boxStart := ← IO.mkRef none,
    boxConfig := ← IO.mkRef {}, group := ← IO.mkRef none
    dragMode := ← IO.mkRef .pan, wheelMode := ← IO.mkRef .zoom, touchMode := ← IO.mkRef .on, cursorMode := ← IO.mkRef .off, cursorDotted := ← IO.mkRef false, markerMode := ← IO.mkRef .off, markerStyle := ← IO.mkRef {}, tooltipStyle := ← IO.mkRef none, numberFormat := ← IO.mkRef none, legendStyle := ← IO.mkRef none, hidden := ← IO.mkRef #[], hiddenGroups := ← IO.mkRef #[], selectMode := ← IO.mkRef .off, band := ← IO.mkRef none, selectDrag := ← IO.mkRef none, cursor := ← IO.mkRef none
    frame := ← IO.mkRef Frame.initial, scheduled := ← IO.mkRef false, alive := ← IO.mkRef true
    size := ← IO.mkRef ⟨0, 0⟩, ratio := ← IO.mkRef 1000, scene := ← IO.mkRef none
    generation := ← IO.mkRef 0, frameCallback := ← IO.mkRef none, observer := ← IO.mkRef none, sceneSize := ← IO.mkRef ((0, 0), (0, 0)), resizes := ← IO.mkRef 0
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

private def announceView (c : Chart) (scene : Scene) (view : View Float) : IO Unit := do
  let x := view.x
  let y := view.y
  dispatch c.el "inkproof-view" (obj [("xStart", toJS x.start), ("xEnd", toJS (x.start + x.span)),
    ("yStart", toJS y.start), ("yEnd", toJS (y.start + y.span))])
  refreshSummary c scene.access
  setText c (scene.access.summaryText (some view))

/-- The charts in `name` that can be navigated, in the order they connected, with their state. -/
private def peers (name : String) : IO (Array (Chart × Scene × Nav)) := do
  let mut found := #[]
  for (_, c) in (← live.get).toArray.qsort (·.1 < ·.1) do
    if (← c.group.get) == some name then
      if let (some scene, some nav) := (← c.scene.get, ← c.nav.get) then
        if scene.access.view.isSome then found := found.push (c, scene, nav)
  return found

/-- Make `band` the chart's selection and tell the application, without telling the chart's group. -/
private def applyBand (c : Chart) (band : Option (Selection.Band Float)) : IO Unit := do
  if (← c.band.get) == band then return
  c.band.set band
  let edge (f : Selection.Band Float → Float) : Data := match band with
    | some b => toJS (f b)
    | none => .null
  dispatch c.el "inkproof-select" (obj [("xStart", edge (·.lo)), ("xEnd", edge (·.hi))])
  invalidate c

/-- Give every other chart in `origin`'s group the x range of `view`, which is the origin's, and tell each that changed. A chart that selects keeps its own range and moves its band to it. -/
private def followFrom (origin : Chart) (view : View Float) : IO Unit := do
  let some name ← origin.group.get | return
  let members ← peers name
  let some i := members.findIdx? (·.1.id == origin.id) | return
  let views := Linked.followArray (members.map (·.2.2.view)) i view
  for h : j in [0:members.size] do
    let (c, scene, nav) := members[j]
    if j == i then continue
    if (← c.selectMode.get) != .off then
      if let some config := scene.access.view then applyBand c (Select.following config view)
    else
      let next := views[j]?.getD nav.view
      if next != nav.view then
        c.nav.set (some { nav with view := next })
        log .debug "chart followed its group" [("group", name), ("chart", toString c.id)]
        announceView c scene next

/-- The view a chart gives its group: its own, or for one that selects, the one that shows its band. -/
private def groupView (c : Chart) (nav : Nav) : IO (View Float) := do
  match ← c.band.get with
  | some band => return Select.shown nav.view band
  | none => return nav.view

/-- Make `band` the chart's selection, and the x range of the rest of its group. -/
private def selectBand (c : Chart) (band : Option (Selection.Band Float)) : IO Unit := do
  applyBand c band
  if let (some band, some nav) := (band, ← c.nav.get) then followFrom c (Select.shown nav.view band)

/-- The scene's value groups with the legend's choice of which are hidden. -/
private def activeGroups (c : Chart) (scene : Scene) : IO (Array ValueGroup) := do
  let mask ← c.hiddenGroups.get
  return scene.access.groups.mapIdx fun i g => { g with hidden := g.hideable && mask[i]?.getD g.hidden }

/-- Keep the legend's hidden series across scenes, unless the new scene has a different number of series, when its own flags apply. -/
private def adoptTraces (c : Chart) (scene : Scene) : IO Unit :=
  c.hidden.modify fun mask =>
    if mask.size == scene.access.traces.size then mask else scene.access.traces.map (·.hidden)

private def showTooltip (c : Chart) (scene : Scene) : IO Unit := do
  let off : IO Unit := do
    c.tip.get "style" Value >>= (·.set "display" "none")
    c.tip.set "textContent" ""
  let (some tip, some (x, y), some config) := (← c.tooltipStyle.get, ← c.cursor.get, scene.access.view) | off
  let fmt ← c.numberFormat.get
  let view := ((← c.nav.get).map (·.view)).getD (View.home config)
  let traces ← activeTraces c scene
  let py := (y.map fun y => config.y.length - view.y.toScreen config.y y).getD 0
  let px := view.x.toScreen config.x x
  let screen := traces.map (·.onScreen config view)
  match Nearest.find tip.metric screen px py, (tip.metric == .plane && y.isNone) with
  | some hit, false =>
    let text := if tip.shared then Tooltip.sharedText fmt tip.showX traces x else Tooltip.single fmt tip.showX traces hit
    match text with
    | some text =>
      let style ← c.tip.get "style" Value
      c.tip.set "textContent" text
      style.set "left" "0px"
      style.set "top" "0px"
      style.set "display" "block"
      let (ox, oy) := scene.access.plotOrigin
      let (ax, ay) := match tip.anchor, y with
        | .pointer, some _ => (px, py)
        | _, _ => (hit.x, hit.y)
      let size ← c.tip.callMethod "getBoundingClientRect" #[] Value
      let canvasTop ← c.canvas.get "offsetTop" Float
      let (left, top) := tip.place (ox + ax) (canvasTop + oy + ay) (← size.get "width" Float) (← size.get "height" Float)
        (← c.el.get "clientWidth" Float) (← c.el.get "clientHeight" Float)
      style.set "left" s!"{left}px"
      style.set "top" s!"{top}px"
    | none => off
  | _, _ => off

private def placeName : Legend.Placement → String
  | .topLeft => "top-left"
  | .topRight => "top-right"
  | .bottomLeft => "bottom-left"
  | .bottomRight => "bottom-right"
  | .belowLeft => "below-left"
  | .belowCenter => "below-center"
  | .belowRight => "below-right"

/-- Show `title` above the plot, or nothing: the canvas, and the size a loader is given, are the element less the title's row. -/
private def setTitle (c : Chart) (title : Option String) : IO Unit := do
  match title with
  | some t =>
    c.titleEl.set "textContent" t
    c.el.callMethod "setAttribute" #[toJS "data-title", toJS ""] Unit
  | none =>
    c.titleEl.set "textContent" ""
    c.el.callMethod "removeAttribute" #[toJS "data-title"] Unit

/-- Take up a legend style: the stylesheet places the legend by the attributes this sets on it and on the element. -/
private def setLegendStyle (c : Chart) (style : Option Legend.Style) : IO Unit := do
  c.legendStyle.set style
  let below := style.any (·.placement.isBelow)
  if below then c.el.callMethod "setAttribute" #[toJS "data-legend-below", toJS ""] Unit
  else c.el.callMethod "removeAttribute" #[toJS "data-legend-below"] Unit
  if let some style := style then
    c.legendEl.callMethod "setAttribute" #[toJS "data-place", toJS (placeName style.placement)] Unit
    c.legendEl.callMethod "setAttribute" #[toJS "data-layout", toJS (if style.layout == .vertical then "vertical" else "horizontal")] Unit

private def showLegend (c : Chart) (scene : Scene) : IO Unit := do
  let doc ← (← global).get "document"
  c.legendEl.callMethod "replaceChildren" #[] Unit
  let some style ← c.legendStyle.get | return
  let live := style.live
  let cursor ← if live || style.showX || style.showY then c.cursor.get else pure none
  let cursorX := cursor.map (·.1)
  let fmt ← c.numberFormat.get
  if let some (x, y) := cursor then
    if let some text := Legend.readout fmt style.showX style.showY x y then
      let readout ← newElement doc "div"
      readout.set "className" "readout"
      readout.set "textContent" text
      c.legendEl.callMethod "append" #[toJS readout] Unit
  let rows := Legend.rows (← activeTraces c scene) cursorX
  for (row, i) in rows.zipIdx do
    let button ← newElement doc "button"
    button.callMethod "setAttribute" #[toJS "data-series", toJS (toString i)] Unit
    button.callMethod "setAttribute" #[toJS "aria-pressed", toJS (toString !row.hidden)] Unit
    let swatch ← newElement doc "span"
    swatch.set "className" "swatch"
    (← swatch.get "style" Value).set "background" row.color
    let label ← newElement doc "span"
    label.set "textContent" (if live then Legend.text fmt row else row.name)
    button.callMethod "append" #[toJS swatch, toJS label] Unit
    c.legendEl.callMethod "append" #[toJS button] Unit
  for (g, gi) in (← activeGroups c scene).zipIdx do
    for row in Legend.groupRows g cursorX do
      let entry ← newElement doc (if g.hideable then "button" else "div")
      if g.hideable then
        entry.callMethod "setAttribute" #[toJS "data-group", toJS (toString gi)] Unit
        entry.callMethod "setAttribute" #[toJS "aria-pressed", toJS (toString !row.hidden)] Unit
      else entry.set "className" "entry"
      let swatch ← newElement doc "span"
      swatch.set "className" "swatch"
      (← swatch.get "style" Value).set "background" row.color
      let label ← newElement doc "span"
      label.set "textContent" (if live then Legend.text fmt row else row.name)
      entry.callMethod "append" #[toJS swatch, toJS label] Unit
      c.legendEl.callMethod "append" #[toJS entry] Unit

/-- Bring the tooltip and legend up to date with the cursor, the scene and the hidden series. -/
private def refreshProbe (c : Chart) : IO Unit := do
  if let some scene ← c.scene.get then
    showTooltip c scene
    showLegend c scene

/-- Put the cursor at `pos`, or take it away, and redraw if that changed it. -/
private def moveCursor (c : Chart) (pos : Option (Float × Option Float)) : IO Unit := do
  let old ← c.cursor.get
  let same := match old, pos with
    | none, none => true
    | some (x₁, y₁), some (x₂, y₂) => x₁ == x₂ && y₁ == y₂
    | _, _ => false
  unless same do
    c.cursor.set pos
    refreshProbe c
    if (← c.cursorMode.get) != .off || (← c.markerMode.get) != .off then invalidate c

/-- Show the cursor at x position `x` on every other chart in `origin`'s group, which share the axis, or take it from them. -/
private def shareCursor (origin : Chart) (x : Option Float) : IO Unit := do
  let some name ← origin.group.get | return
  for (c, _, _) in ← peers name do
    if c.id != origin.id then moveCursor c (x.map (·, none))

/-- Make `next` the chart's state, telling the application and assistive technology of what changed from `nav`, and the chart's group of a new x range. -/
private def commit (c : Chart) (scene : Scene) (nav next : Nav) : IO Unit := do
  c.nav.set (some next)
  if next.view != nav.view then
    announceView c scene next.view
    followFrom c next.view
  if next.point != nav.point || next.series != nav.series then
    dispatch c.el "inkproof-cursor" (obj [("series", toJS next.series), ("point", toJS next.point)])
    setText c (scene.access.cursorText next)

private def navigable (c : Chart) : IO (Option (Scene × NavConfig × Nav)) := do
  let some scene ← c.scene.get | return none
  let some config := scene.access.view | return none
  let some nav ← c.nav.get | return none
  return some (scene, ⟨config, scene.access.points, scene.access.series.size⟩, nav)

/-- Tell the stylesheet which touch gestures the chart takes from the browser. -/
private def syncTouch (c : Chart) : IO Unit := do
  let hasView := (← c.scene.get).any (·.access.view.isSome)
  let action := TouchAction.of hasView (← c.touchMode.get) (← c.dragMode.get) (← c.selectMode.get)
  let value := match action with
    | .auto => none
    | .panY => some "pan-y"
    | .panXY => some "pan-xy"
    | .none => some "none"
  match value with
  | some v => c.el.callMethod "setAttribute" #[toJS "data-touch-action", toJS v] Unit
  | none => c.el.callMethod "removeAttribute" #[toJS "data-touch-action"] Unit

private def onKey (c : Chart) (event : Value) : IO Unit := do
  let some (scene, navConfig, nav) ← navigable c | return
  let held (flag : String) : IO Bool := event.get flag Bool
  if (← held "ctrlKey") || (← held "altKey") || (← held "metaKey") then return
  let key ← event.get "key" String
  let some command := Command.ofKey key (← held "shiftKey") | return
  if (← c.selectMode.get) != .off then
    if let .view _ := command then return
  event.callMethod "preventDefault" #[] Unit
  commit c scene nav (nav.apply navConfig command)

/-- The pointer's position in pixels from the plot's top left. -/
private def position (c : Chart) (event : Value) : IO Px := do
  let rect ← c.canvas.callMethod "getBoundingClientRect" #[]
  let origin := ((← c.scene.get).map (·.access.plotOrigin)).getD (0, 0)
  return ((← event.get "clientX" Float) - (← rect.get "left" Float) - origin.1,
          (← event.get "clientY" Float) - (← rect.get "top" Float) - origin.2)

private def applyInputs (c : Chart) (inputs : List (Input Float)) : IO Unit := do
  let some (scene, navConfig, nav) ← navigable c | return
  commit c scene nav (inputs.foldl (·.input navConfig ·) nav)

private def onWheel (c : Chart) (event : Value) : IO Unit := do
  if (← c.selectMode.get) != .off then return
  let held (flag : String) : IO Bool := event.get flag Bool
  unless (← c.wheelMode.get).zooms (← held "ctrlKey") (← held "metaKey") do return
  let some (_, navConfig, _) ← navigable c | return
  let pos ← position c event
  unless Gesture.inside navConfig.view pos do return
  event.callMethod "preventDefault" #[] Unit
  let scale : Float := if (← event.get "deltaMode" Nat) == 1 then 16 else 1
  let p := Gesture.toView navConfig.view pos
  let factor := Gesture.wheelFactor (scale * (← event.get "deltaY" Float))
  applyInputs c [.wheel p.1 p.2 factor]

/-- The data x position at plot position `p`. -/
private def dataX (navConfig : NavConfig) (nav : Nav) (p : Px) : Float :=
  let v := Gesture.toView navConfig.view p
  (View.cursor navConfig.view nav.view v.1 v.2).1

private def onPointerDown (c : Chart) (event : Value) : IO Unit := do
  let some (_, navConfig, nav) ← navigable c | return
  let id ← event.get "pointerId" Nat
  let p ← position c event
  unless Gesture.inside navConfig.view p do return
  if (← event.get "pointerType" String) == "touch" && (← c.touchMode.get) == .off then return
  if (← c.selectMode.get) != .off then
    if (← c.selectDrag.get).isNone then
      try c.el.callMethod "setPointerCapture" #[toJS id] Unit
      catch e => log .warn "pointer capture failed, continuing without it" [("error", toString e)]
      let x := dataX navConfig nav p
      c.selectDrag.set (some (Selection.press (Select.config navConfig.view) (← c.band.get) x))
    return
  let mode ← c.dragMode.get
  -- A mouse has no gesture but the drag; a touch is still tracked for a pinch.
  if mode == .off && (← event.get "pointerType" String) != "touch" then return
  c.pointers.modify (·.filter (·.1 != id) |>.push (id, p))
  -- A pointer the browser no longer considers active cannot be captured; the gesture still works.
  try c.el.callMethod "setPointerCapture" #[toJS id] Unit
  catch e => log .warn "pointer capture failed, continuing without it" [("error", toString e)]
  let boxes := mode.boxes (← event.get "shiftKey" Bool)
  c.boxStart.set (if (← c.pointers.get).size == 1 && boxes then some p else none)

/-- A click on a legend entry hides or shows its series, and tells the application, which answers by drawing the scene without it. -/
private def onLegendClick (c : Chart) (event : Value) : IO Unit := do
  let target ← event.get "target" Value
  let some button ← Web.Support.optionalValue (← target.callMethod "closest" #[toJS "button"] Data) | return
  let some scene ← c.scene.get | return
  if ← button.callMethod "hasAttribute" #[toJS "data-group"] Bool then
    let some index := (← button.callMethod "getAttribute" #[toJS "data-group"] String).toNat? | return
    let groups ← activeGroups c scene
    let some g := groups[index]? | return
    let hidden := groups.mapIdx fun i h => if i == index then !g.hidden else h.hidden
    c.hiddenGroups.set hidden
    dispatch c.el "inkproof-group" (obj [("group", toJS index), ("hidden", .bool !g.hidden)])
    refreshProbe c
    return
  let some index := (← button.callMethod "getAttribute" #[toJS "data-series"] String).toNat? | return
  let hidden := (Legend.toggle (← activeTraces c scene) index).map (·.hidden)
  c.hidden.set hidden
  dispatch c.el "inkproof-series" (obj [("series", toJS index), ("hidden", .bool (hidden[index]?.getD false))])
  refreshProbe c

private def clearCursor (c : Chart) : IO Unit := do
  moveCursor c none
  shareCursor c none

private def onPointerLeave (c : Chart) (_ : Value) : IO Unit := clearCursor c

private def onPointerMove (c : Chart) (event : Value) : IO Unit := do
  let some (_, navConfig, nav) ← navigable c | return
  let id ← event.get "pointerId" Nat
  let p ← position c event
  let tracked ← c.pointers.get
  if let some drag ← c.selectDrag.get then
    selectBand c (Selection.Drag.at (Select.config navConfig.view) drag (dataX navConfig nav p))
  if tracked.any (·.1 == id) then
    let toView := Gesture.toView navConfig.view
    let moved := tracked.map fun t => if t.1 == id then (id, p) else t
    c.pointers.set moved
    match tracked, moved with
    | #[(_, o₁), (_, o₂)], #[(_, n₁), (_, n₂)] =>
      applyInputs c (Gesture.pinch (toView o₁) (toView o₂) (toView n₁) (toView n₂))
    | #[(_, old)], _ =>
      if (← c.boxStart.get).isNone && (← c.dragMode.get) != .off then
        let o := toView old
        let n := toView p
        applyInputs c [.drag (n.1 - o.1) (n.2 - o.2)]
    | _, _ => pure ()
  if Gesture.inside navConfig.view p then
    let v := Gesture.toView navConfig.view p
    let d := View.cursor navConfig.view ((← c.nav.get).getD nav).view v.1 v.2
    dispatch c.el "inkproof-pointer" (obj [("x", toJS d.1), ("y", toJS d.2)])
    moveCursor c (some (d.1, some d.2))
    shareCursor c (some d.1)
  else
    clearCursor c

private def onPointerUp (c : Chart) (event : Value) : IO Unit := do
  let id ← event.get "pointerId" Nat
  c.selectDrag.set none
  if let some start ← c.boxStart.get then
    c.boxStart.set none
    if (← event.get "type" String) == "pointerup" then
      if let some (_, navConfig, _) ← navigable c then
        if let some input := (← c.boxConfig.get).input navConfig.view start (← position c event) then applyInputs c [input]
  c.pointers.modify (·.filter (·.1 != id))

/-- Take the x range of the chart's group, if others are in it. -/
private def joinGroup (c : Chart) : IO Unit := do
  let some name ← c.group.get | return
  if let some (p, _, nav) := (← peers name).find? (·.1.id != c.id) then followFrom p (← groupView p nav)

private def applyCursorStyle (c : Chart) (style : CursorStyle) : IO Unit := do
  c.cursorMode.set style.lines
  c.cursorDotted.set style.dotted
  c.markerMode.set style.markers
  c.markerStyle.set style.marker

private def applyInteraction (c : Chart) (i : Interaction) : IO Unit := do
  c.wheelMode.set i.wheel
  c.touchMode.set i.touch
  c.dragMode.set i.drag
  c.boxConfig.set i.box
  c.selectMode.set i.select

private def load (c : Chart) (loader : Loader) : Async Unit := do
  let src ← getAttr c.el "src"
  let level ← getAttr c.el "log-level"
  let groupName ← getAttr c.el "group"
  let cursorName ← getAttr c.el "cursor"
  let interactionName ← getAttr c.el "interaction"
  let tooltipName ← getAttr c.el "tooltip"
  let legendName ← getAttr c.el "legend"
  let numbersName ← getAttr c.el "number-format"
  setTitle c (← getAttr c.el "chart-title")
  match ChartAttrs.parse src level, Group.parse groupName, CursorStyle.parse cursorName, Interaction.parse interactionName,
      Tooltip.parse tooltipName, Legend.parseStyle legendName, Numbers.parse numbersName with
  | .error message, _, _, _, _, _, _ | _, .error message, _, _, _, _, _ | _, _, .error message, _, _, _, _
  | _, _, _, .error message, _, _, _ | _, _, _, _, .error message, _, _ | _, _, _, _, _, .error message, _
  | _, _, _, _, _, _, .error message => fail c message []
  | .ok attrs, .ok group, .ok cursor, .ok interaction, .ok tooltip, .ok legend, .ok numbers =>
    c.tooltipStyle.set tooltip
    c.numberFormat.set numbers
    setLegendStyle c legend
    applyCursorStyle c cursor
    applyInteraction c interaction
    c.group.set group
    if let some l := attrs.logLevel then setThreshold l
    c.generation.modify (· + 1)
    let generation ← c.generation.get
    try
      let sizes ← sceneSizes c
      c.sceneSize.set sizes
      let scene ← loader attrs.src sizes.1 sizes.2
      -- A newer load or a disconnect has overtaken this one.
      if (← c.generation.get) == generation && (← c.alive.get) then
        c.scene.set (some scene)
        syncTouch c
        adoptTraces c scene
        publish c scene.access
        refreshProbe c
        joinGroup c
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
  syncTouch c
  adoptTraces c scene
  c.nav.set (match scene.access.view, kept with
    | some _, some nav => some nav
    | some v, none => some (Nav.home ⟨v, scene.access.points, scene.access.series.size⟩)
    | none, _ => none)
  describe c scene.access
  refreshProbe c
  invalidate c

/-- Make the scene again for the canvas's size, once it has stopped changing, keeping the chart's view. -/
private def settle (c : Chart) (loader : Loader) : IO Unit := do
  let sizes ← sceneSizes c
  if sizes == (← c.sceneSize.get) || sizes.1.1 == 0 || sizes.1.2 == 0 then return
  let token ← c.resizes.modifyGet fun n => (n + 1, n + 1)
  let fire ← Function.ofFn fun _ => do
    if (← c.alive.get) && (← c.resizes.get) == token then
      let sizes ← sceneSizes c
      c.sceneSize.set sizes
      try
        let scene ← loader ((← getAttr c.el "src").getD "") sizes.1 sizes.2
        if (← c.alive.get) && (← c.resizes.get) == token then setScene c.el scene
      catch e =>
        fail c s!"making the scene for the new size failed: {e}" [("size", s!"{sizes.1.1}x{sizes.1.2}")]
    return .undefined
  discard <| (← global).callMethod "setTimeout" #[toJS fire, toJS (150 : Nat)] Value

/-- Put the chart's cursor at x position `x` in data coordinates, or take it away, as the pointer over a chart outside its group would. -/
def setCursor (el : Value) (x : Option Float) : IO Unit := do
  let some c ← chartOfElement el | return
  unless (← c.alive.get) do return
  moveCursor c (x.map (·, none))

/-- Select the x range `range` of a chart with the `select` attribute, as a drag would, or clear its selection. Other charts in its group take the range as theirs. -/
def setSelection (el : Value) (range : Option (Float × Float)) : IO Unit := do
  let some c ← chartOfElement el | return
  unless (← c.alive.get) && (← c.selectMode.get) != .off do return
  let some (_, navConfig, _) ← navigable c | return
  selectBand c (range.bind fun (lo, hi) => Selection.draw (Select.config navConfig.view) lo hi)

/-- Apply `command` to the chart as the key for it would, telling the application of what changed. -/
def apply (el : Value) (command : Command) : IO Unit := do
  let some c ← chartOfElement el | return
  let some (scene, navConfig, nav) ← navigable c | return
  commit c scene nav (nav.apply navConfig command)

/-- The view an `inkproof-view` event reports, from its `detail`. -/
def viewOf (detail : Value) : IO (View Float) :=
  return View.ofBounds (← detail.get "xStart" Float) (← detail.get "xEnd" Float) (← detail.get "yStart" Float) (← detail.get "yEnd" Float)

/-- The data position an `inkproof-pointer` event reports, from its `detail`. -/
def pointerOf (detail : Value) : IO (Float × Float) :=
  return (← detail.get "x" Float, ← detail.get "y" Float)

initialize buttonsHandled : IO.Ref Bool ← IO.mkRef false

/-- The element a button's attribute `name` gives the id of, with the button, if the click reached one. -/
private def buttonTarget (event : Value) (name : String) : IO (Option (Value × Value)) := do
  let hit ← (← event.get "target" Value).callMethod "closest" #[toJS s!"button[{name}]"] Data
  let .ref button _ := hit | return none
  let id ← button.callMethod "getAttribute" #[toJS name] String
  let found ← (← (← global).get "document").callMethod "getElementById" #[toJS id] Data
  let .ref el _ := found | do
    log .warn "a button names no chart" [("attribute", name), ("id", id)]
    return none
  return some (button, el)

/-- Answer clicks on `button[data-reset]`, which resets the chart whose id it holds, and on `button[data-unlink]`, which takes that chart out of its group, or puts it back in the one the button's `data-group` names. -/
private def handleButtons : IO Unit := do
  if ← buttonsHandled.get then return
  buttonsHandled.set true
  let click ← Function.ofSyncFn fun args => do
    let some (Data.ref event _) := args[0]? | return .undefined
    if let some (_, el) ← buttonTarget event "data-reset" then apply el .reset
    if let some (button, el) ← buttonTarget event "data-unlink" then
      match Group.toggled (← getAttr el "group") (← getAttr button "data-group") with
      | some name => el.callMethod "setAttribute" #[toJS "group", toJS name] Unit
      | none => el.callMethod "removeAttribute" #[toJS "group"] Unit
    return .undefined
  (← (← global).get "document").callMethod "addEventListener" #[toJS "click", toJS click] Unit

private def chartOf (args : Array Data) : IO (Option Chart) := do
  let some (Data.ref el _) := args[0]? | return none
  chartOfElement el

private def connect (loader : Loader) (resizes : Bool) (args : Array Data) : Async Unit := do
  let some (Data.ref el _) := args[0]? | return
  let id ← nextId.modifyGet fun n => (n, n + 1)
  let c ← build id el
  el.set idKey id
  live.modify (·.insert id c)
  for (name, handler) in [("keydown", onKey c), ("wheel", onWheel c), ("pointerdown", onPointerDown c),
      ("pointermove", onPointerMove c), ("pointerleave", onPointerLeave c), ("pointerup", onPointerUp c), ("pointercancel", onPointerUp c)] do
    let listener ← Function.ofSyncFn fun args => do
      if let some (Data.ref event _) := args[0]? then handler event
      return .undefined
    let options := if name == "wheel" then obj [("passive", .bool false)] else obj []
    el.callMethod "addEventListener" #[toJS name, toJS listener, options] Unit
    c.listeners.modify (·.push (name, listener))
  let legendClick ← Function.ofSyncFn fun args => do
    if let some (Data.ref event _) := args[0]? then onLegendClick c event
    return .undefined
  c.legendEl.callMethod "addEventListener" #[toJS "click", toJS legendClick] Unit
  -- Gestures on the chart capture the pointer, which would retarget the click away from the entry.
  let keepPress ← Function.ofSyncFn fun args => do
    if let some (Data.ref event _) := args[0]? then event.callMethod "stopPropagation" #[] Unit
    return .undefined
  c.legendEl.callMethod "addEventListener" #[toJS "pointerdown", toJS keepPress] Unit
  c.frameCallback.set (some (← Function.ofSyncFn fun _ => do onFrame c; return .undefined))
  let observe ← Function.ofSyncFn fun _ => do
    if (← c.alive.get) then
      sync c
      if resizes then settle c loader
    return .undefined
  let observer ← (← (← global).get "ResizeObserver").new #[toJS observe]
  observer.callMethod "observe" #[toJS el] Unit
  observer.callMethod "observe" #[toJS c.canvas] Unit
  c.observer.set (some observer)
  watchRatio c (if resizes then settle c loader else pure ())
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

/-- A change of `group` moves the chart between groups without reloading it. -/
private def regroup (c : Chart) (value : Option String) : IO Unit := do
  match Group.parse value with
  | .error message => fail c message []
  | .ok group =>
    c.group.set group
    joinGroup c

/-- A change of `cursor` redraws the chart without reloading it. -/
private def recursor (c : Chart) (value : Option String) : IO Unit := do
  match CursorStyle.parse value with
  | .error message => fail c message []
  | .ok style =>
    applyCursorStyle c style
    invalidate c

/-- A change of `tooltip`, `legend` or `number-format` redraws them without reloading the chart. -/
private def reprobe (c : Chart) (tooltip legend numbers : Option String) : IO Unit := do
  match Tooltip.parse tooltip, Legend.parseStyle legend, Numbers.parse numbers with
  | .error message, _, _ | _, .error message, _ | _, _, .error message => fail c message []
  | .ok t, .ok l, .ok n =>
    c.tooltipStyle.set t
    c.numberFormat.set n
    setLegendStyle c l
    refreshProbe c

/-- A change of `interaction` takes effect for the next gesture, without reloading the chart; a selection that is no longer wanted loses its band. -/
private def reinput (c : Chart) (value : Option String) : IO Unit := do
  match Interaction.parse value with
  | .error message => fail c message []
  | .ok i =>
    applyInteraction c i
    c.selectDrag.set none
    c.pointers.set #[]
    c.boxStart.set none
    syncTouch c
    if i.select == .off then applyBand c none
    invalidate c

private def changed (loader : Loader) (args : Array Data) : Async Unit := do
  if let some c ← chartOf args then
    if (← c.alive.get) then
      match args[1]? with
      | some (.string "group") => regroup c (← getAttr c.el "group")
      | some (.string "cursor") => recursor c (← getAttr c.el "cursor")
      | some (.string "interaction") => reinput c (← getAttr c.el "interaction")
      | some (.string "chart-title") => setTitle c (← getAttr c.el "chart-title")
      | some (.string "tooltip") | some (.string "legend") | some (.string "number-format") =>
        reprobe c (← getAttr c.el "tooltip") (← getAttr c.el "legend") (← getAttr c.el "number-format")
      | _ => load c loader

private def define (tag : String) (loader : Loader) (resizes buttons : Bool) : IO Unit := do
  if buttons then handleButtons
  redrawAll.set do
    for (_, chart) in (← live.get) do invalidate chart
  defineElement tag #["src", "log-level", "group", "cursor", "interaction", "tooltip", "legend", "number-format", "chart-title"]
    (← Function.ofFn (connect loader resizes · *> pure .undefined))
    (← Function.ofSyncFn disconnect)
    (← Function.ofFn (changed loader · *> pure .undefined))

/-- Define the custom element `tag`: it draws the scene `loader` makes of its `src` attribute. With `buttons`, the page's `button[data-reset]` and `button[data-unlink]` act on the charts they name, with no page code. -/
def register (tag : String) (loader : String → Async Scene := fetchScene) (buttons : Bool := false) : IO Unit :=
  define tag (fun src _ _ => loader src) false buttons

/-- Like `register`, for a chart whose scene depends on its size: `loader` is given the `src` and the canvas's CSS width and height, and is called again, after the size has stopped changing for a moment, with the new size. The chart keeps its view, cursor and hidden series across the new scene. -/
def registerSized (tag : String) (loader : String → Nat → Nat → Async Scene) (buttons : Bool := false) : IO Unit :=
  define tag (fun src css _ => loader src css.1 css.2) true buttons

/-- Like `registerSized`, for a chart whose commands are in device pixels, such as a Gpu frame for a target of a given size: `loader` is given the backing store's size too, which follows the device pixel ratio, and is called again when either size changes. A clip or a stroke width in the commands is then in the pixels of the canvas, whatever the ratio. -/
def registerPixels (tag : String) (loader : String → Nat × Nat → Nat × Nat → Async Scene) (buttons : Bool := false) : IO Unit :=
  define tag loader true buttons

end Inkproof.Web.Host
