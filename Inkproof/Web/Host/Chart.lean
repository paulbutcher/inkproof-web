/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Support
import Lasm.JS.Web.Fetch
import Std.Data.HashMap
import Inkproof.Web.Surface
import Inkproof.Web.Frame
import Inkproof.Web.Attr
import Inkproof.Web.Host.Console
import Inkproof.Web.Host.Gpu
import Inkproof.Web.Host.Element

namespace Inkproof.Web.Host
open Lasm.JS

/-- A piece of text for the Canvas 2D layer, in CSS pixels from the chart's top left. -/
structure Label where
  text : String
  x : Float
  y : Float
  font : String := "12px sans-serif"
  color : String := "#000"

/-- What a chart shows: the encoded Gpu command list for the data layers, and the text over them. -/
structure Scene where
  commands : ByteArray
  labels : Array Label := #[]

/-- Fetch `src` and take its body as the command list. -/
def fetchScene (src : String) : Async Scene := do
  let response ← Web.fetch (.usvString src)
  unless (← response.ok) do
    throw (IO.userError s!"fetching {src} gave status {← response.status}")
  return { commands := ← response.bytes }

private structure Shared where
  canvas : Value
  gl : Value

private structure Chart where
  id : Nat
  el : Value
  canvas : Value
  ctx : Value
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
initialize live : IO.Ref (Std.HashMap Nat Chart) ← IO.mkRef {}
initialize nextId : IO.Ref Nat ← IO.mkRef 0
/-- Redraws every chart; set once `schedule` exists, since drawing is what creates the context that reports its restoration. -/
initialize redrawAll : IO.Ref (IO Unit) ← IO.mkRef (pure ())

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
  let s := gl.map fun gl => { canvas, gl : Shared }
  shared.set (some s)
  if let some s := s then
    let lost ← Function.ofSyncFn fun args => do
      if let some (Data.ref e _) := args[0]? then discard <| e.callMethod "preventDefault" #[] Unit
      contextLost.set true
      log .warn "WebGL context lost, waiting for restoration" []
      return .undefined
    let restored ← Function.ofSyncFn fun _ => do
      contextLost.set false
      log .warn "WebGL context restored, redrawing" [("charts", toString (← live.get).size)]
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
    run s.gl (← newState) scene.commands
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
    c.ctx.callMethod "fillText" #[toJS label.text, toJS label.x, toJS label.y] Unit
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
  ":host{display:block;width:300px;height:150px}canvas{display:block;width:100%;height:100%}"

private def build (id : Nat) (el : Value) : IO Chart := do
  let doc ← (← global).get "document"
  let root ← match ← Web.Support.optionalValue (← el.get "shadowRoot" Data) with
    | some root => pure root
    | none =>
      let root ← el.callMethod "attachShadow" #[obj [("mode", .string "open")]]
      let style ← doc.callMethod "createElement" #[toJS "style"]
      style.set "textContent" styles
      root.callMethod "append" #[toJS style] Unit
      root.callMethod "append" #[toJS (← doc.callMethod "createElement" #[toJS "canvas"])] Unit
      pure root
  let canvas ← root.callMethod "querySelector" #[toJS "canvas"]
  let ctx ← canvas.callMethod "getContext" #[toJS "2d"]
  return {
    id, el, canvas, ctx
    frame := ← IO.mkRef Frame.initial, scheduled := ← IO.mkRef false, alive := ← IO.mkRef true
    size := ← IO.mkRef ⟨0, 0⟩, ratio := ← IO.mkRef 1000, scene := ← IO.mkRef none
    generation := ← IO.mkRef 0, frameCallback := ← IO.mkRef none, observer := ← IO.mkRef none
    ratioQuery := ← IO.mkRef none }

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
        invalidate c
    catch e =>
      fail c s!"loading the chart failed: {e}" [("src", attrs.src)]

private def chartOf (args : Array Data) : IO (Option Chart) := do
  let some (Data.ref el _) := args[0]? | return none
  match ← el.get idKey Data with
  | .number id => return (← live.get)[id.toUInt64.toNat]?
  | _ => return none

private def connect (loader : String → Async Scene) (args : Array Data) : Async Unit := do
  let some (Data.ref el _) := args[0]? | return
  let id ← nextId.modifyGet fun n => (n, n + 1)
  let c ← build id el
  el.set idKey id
  live.modify (·.insert id c)
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
    if let some o ← c.observer.get then o.callMethod "disconnect" #[] Unit
    if let some (query, changed) ← c.ratioQuery.get then
      query.callMethod "removeEventListener" #[toJS "change", toJS changed] Unit
    live.modify (·.erase c.id)
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
