/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Axis.LabelLayout
import Inkproof.Web.Host.Axis
import Inkproof.Web.Host.Chart
import Inkproof.Web.Host.Measure
import Inkproof.Web.Host.SceneCache
import Inkproof.Gpu.Compile
import Inkproof.Viewport.View

open Lasm.JS Inkproof.Gpu Inkproof.Web Inkproof.Web.Host

/-- The command list from `src`, with Axis-laid-out labels over it, measured by the browser. -/
def labelledScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let texts := (List.range 10).map fun i => s!"label number {i}"
  let measure ← measurer "12px sans-serif" texts.toArray
  let positioned := texts.zipIdx.map fun (text, i) => (20 + 40 * i.toFloat, text)
  let layout := Inkproof.Axis.layoutLabels measure 4 positioned
  return { scene with labels := layout.kept.toArray.map fun (x, text) => { text, x, y := 100 } }

/-- A scene that draws nothing, with a label in the colour of the theme's text, or in none without a theme. -/
def themedScene (_ : String) (_ _ : Nat × Nat) (theme : Option Inkproof.Scene.Theme) : Async Scene := do
  let color := (theme.map fun t => colorCss t.text).getD "#000"
  return { commands := ByteArray.mk (encode [⟨8, [.words []]⟩, ⟨6, [.u32 0]⟩, ⟨7, [.u32 0]⟩]).toArray, labels := #[{ text := "themed", x := 20, y := 100, color }] }

/-- The same text twice: centred on its anchor, and as Scene's vertical label under a bottom axis, a quarter turn anticlockwise with its end at the anchor. -/
def turnedScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let text := "turned label"
  return { scene with labels := #[
    { text, x := 100, y := 100, align := .center, baseline := .middle },
    Label.ofPlaced .bottom { text, anchor := ⟨300, 100⟩, rotation := .vertical }] }

/-- The same text on the left with a second line under it and on the right alone, both centred on their anchors. -/
def secondLineScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let text := "first line"
  return { scene with labels := #[
    { text, second := some "second line", x := 100, y := 60, align := .center, baseline := .top },
    { text, x := 300, y := 60, align := .center, baseline := .top }] }

/-- A plot at x 100 to 350 and y 20 to 150 with tick labels of two widths on its left axis, and the left axis's title if the `axis-title-left` attribute gives one. -/
def axisTitledScene (src : String) (_ _ : Nat × Nat) (_ : Option Inkproof.Scene.Theme) (titles : AxisTitles) : Async Scene := do
  let scene ← fetchScene src
  let r : Inkproof.Scene.Rect := ⟨100, 20, 350, 150⟩
  let labels : List Inkproof.Scene.PlacedLabel :=
    [⟨"5", ⟨94, 120⟩, .horizontal, {}, none⟩, ⟨"1000", ⟨94, 50⟩, .horizontal, {}, none⟩]
  let ticks := Label.ofDrawing .left ⟨#[], labels⟩
  let some text := titles.get .left | return { scene with labels := ticks }
  let title ← axisTitleMeasured .left r {} ⟨#[], labels⟩ text
  return { scene with labels := ticks.push title.label }

/-- A scene with two series of five points, a view over 0 to 100 (400 pixels across and 200 high), and data for the table. -/
def accessibleScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let axis : Inkproof.Viewport.Interval.Config Float :=
    { length := 400, minSpan := 1, maxSpan := 100, home := ⟨0, 100⟩, keyZoom := 2, keyPan := 0.25 }
  return { scene with access :=
    { name := "Sales", series := #["North", "South"], points := 5, view := some ⟨axis, { axis with length := 200 }⟩,
      header := #["Month", "North", "South"],
      rows := #[#["Jan", "1", "2"], #["Feb", "3", "4"]],
      traces := #[
        { name := "North", color := "#d33", xs := #[0, 25, 50, 75, 100], ys := #[10, 30, 20, 60, 40] },
        { name := "South", color := "#36c", xs := #[0, 25, 50, 75, 100], ys := #[80, 70, 90, 50, 55] }] } }

/-- A scene with no series and two groups of values at x of 10, 20 and 30: a candle's open and close, which the chart lets the legend hide, and a state, which it does not. -/
def groupedValuesScene (src : String) : Async Scene := do
  let scene ← accessibleScene src
  return { scene with access := { scene.access with
    traces := #[], series := #[],
    groups := #[
      { name := "Candle", color := "#383", labels := #["Open", "Close"], xs := #[10, 20, 30],
        values := #[#[1, 2], #[3, 4], #[5, 6]], hideable := true },
      { name := "State", color := "#888", labels := #["State"], xs := #[10, 20, 30],
        values := #[#[7], #[8], #[0.0 / 0.0]] }] } }

/-- The accessible scene with two overlapping items and one apart: a described bar over x 10 to 30 and y 0 to 50, a bar over x 20 to 40 and y 0 to 80 with no description, and a described region over x 60 to 80 and y 20 to 60. -/
def itemsScene (src : String) : Async Scene := do
  let scene ← accessibleScene src
  return { scene with access := { scene.access with items := #[
    { x0 := 10, x1 := 30, y0 := 0, y1 := 50, description := some "Bar A" },
    { x0 := 20, x1 := 40, y0 := 0, y1 := 80 },
    { x0 := 60, x1 := 80, y0 := 20, y1 := 60, description := some "Region" }] } }

/-- A scene with one series of 500001 points, over a view of 0 to 500000. -/
def hugeScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let axis : Inkproof.Viewport.Interval.Config Float :=
    { length := 400, minSpan := 1, maxSpan := 500000, home := ⟨0, 500000⟩, keyZoom := 2, keyPan := 0.25 }
  let xs := (Array.range 500001).map Nat.toFloat
  return { scene with access :=
    { name := "Huge", series := #["Wave"], points := 500001, view := some ⟨axis, { axis with length := 200, home := ⟨0, 1⟩, maxSpan := 1 }⟩,
      traces := #[{ name := "Wave", color := "#d33", xs, ys := xs.map fun x => (x - 7 * (x / 7).floor) / 7 }] } }

/-- The same chart with its plot inset by 60 pixels from the left and 20 from the top, in an element large enough to hold it. -/
def insetScene (src : String) : Async Scene := do
  let scene ← accessibleScene src
  return { scene with access := { scene.access with plotOrigin := (60, 20) } }

/-- Answer each view change of `el` with a new scene built from `base`, here the same data with a label naming the range, which keeps the chart's view; a `test-reset` event on `el` resets it. -/
private def answerViews (el : Value) (base : IO.Ref (Option Scene)) : IO Unit := do
  let onView ← Function.ofSyncFn fun args => do
    let some (Data.ref event _) := args[0]? | return .undefined
    let start ← (← event.get "detail" Value).get "xStart" Float
    if let some scene ← base.get then
      setScene el { scene with labels := #[{ text := s!"from {start}", x := 10, y := 10 }] }
    return .undefined
  el.callMethod "addEventListener" #[toJS "inkproof-view", toJS onView] Unit
  let onReset ← Function.ofSyncFn fun _ => do apply el .reset; return .undefined
  el.callMethod "addEventListener" #[toJS "test-reset", toJS onReset] Unit

/-- A label centred 30 pixels in from the right edge and half way down, wherever that is for the canvas size asked for. -/
def sizedScene (src : String) (width height : Nat) : Async Scene := do
  let scene ← fetchScene src
  let x := width.toFloat - 30
  let y := height.toFloat / 2
  return { scene with labels := #[{ text := "MMMM", x, y, align := .center, baseline := .middle }] }

/-- A red quad filling the target, drawn under a scissor that covers the whole backing store; the wire says the scissor is in device pixels from the bottom left. -/
def clippedScene (_ : String) (_css backing : Nat × Nat) : Async Scene := do
  let one : UInt32 := 0x3f800000
  let neg : UInt32 := 0xbf800000
  let words : List UInt32 := [neg, neg, one, neg, neg, one, one, neg, one, one, neg, one]
  let cmds : List Cmd := [⟨8, [.words []]⟩, ⟨6, [.u32 0xffffffff]⟩, ⟨7, [.u32 0]⟩,
    ⟨0, [.u32 0]⟩, ⟨1, [.u32 0, .words words]⟩, ⟨3, [.u32 0]⟩,
    ⟨4, [.u32 0, .words [one, one]]⟩, ⟨4, [.u32 1, .words [0, 0]]⟩, ⟨4, [.u32 2, .words [0]]⟩,
    ⟨4, [.u32 3, .words [one, one, one, one]]⟩, ⟨4, [.u32 4, .words [0, 0, one, one]]⟩,
    ⟨8, [.words [0, 0, backing.1.toUInt32, backing.2.toUInt32]]⟩,
    ⟨5, [.u32 0, .u32 6, .u32 2]⟩]
  return { commands := ByteArray.mk (encode cmds).toArray }

/-- A scene that draws one buffer, uploaded only when the cache does not hold it. -/
def cachedScene (cache : SceneCache) : IO Scene :=
  cache.build fun c fresh => do
    let one : UInt32 := 0x3f800000
    let words : List UInt32 := [one, one, 0, one, one, 0]
    let (c', handle, setup) : Cache × Nat × List Cmd := match c.entries.find? (·.words == [words]) with
      | some e => (c, e.base, [])
      | none => ({ entries := ⟨[words], c.next⟩ :: c.entries, next := c.next + 1 }, c.next,
          [⟨0, [.u32 c.next.toUInt32]⟩, ⟨1, [.u32 c.next.toUInt32, .words words]⟩])
    let prologue : List Cmd := if fresh then [⟨8, [.words []]⟩, ⟨6, [.u32 0xff8000ff]⟩, ⟨7, [.u32 0]⟩] else []
    let draw : List Cmd := [⟨3, [.u32 0]⟩, ⟨4, [.u32 0, .words [one, one]]⟩, ⟨4, [.u32 1, .words [0, 0]]⟩,
      ⟨4, [.u32 2, .words [0]]⟩, ⟨4, [.u32 3, .words [one, one, one, one]]⟩, ⟨4, [.u32 4, .words [0, 0, one, one]]⟩,
      ⟨5, [.u32 handle.toUInt32, .u32 3, .u32 2]⟩]
    return (c', { commands := ByteArray.mk (encode (prologue ++ setup ++ draw)).toArray })

/-- Draw the chart again from its cache on each `test-redraw` event, and from an emptied one after `test-invalidate`. -/
private def redrawOnRequest (el : Value) (cache : SceneCache) : IO Unit := do
  let redraw ← Function.ofSyncFn fun _ => do setScene el (← cachedScene cache); return .undefined
  el.callMethod "addEventListener" #[toJS "test-redraw", toJS redraw] Unit
  let invalidate ← Function.ofSyncFn fun _ => do cache.invalidate; return .undefined
  el.callMethod "addEventListener" #[toJS "test-invalidate", toJS invalidate] Unit

def main : IO Unit := do
  let cache ← SceneCache.new
  register "inkproof-cached-chart" fun _ => do cachedScene cache
  register "inkproof-accessible-chart" accessibleScene (buttons := true)
  let base ← IO.mkRef none
  register "inkproof-replacing-chart" fun src => do
    let scene ← accessibleScene src
    base.set (some scene)
    return scene
  register "inkproof-values-chart" groupedValuesScene
  register "inkproof-huge-chart" hugeScene
  register "inkproof-inset-chart" insetScene
  register "inkproof-items-chart" itemsScene
  register "inkproof-chart"
  register "inkproof-labelled-chart" labelledScene
  register "inkproof-turned-chart" turnedScene
  registerTitled "inkproof-axis-title-chart" axisTitledScene
  register "inkproof-second-chart" secondLineScene
  registerSized "inkproof-sized-chart" sizedScene
  registerThemed "inkproof-themed-chart" themedScene
  registerPixels "inkproof-pixel-chart" clippedScene
  let doc ← (← global).get "document"
  if let .ref el _ ← doc.callMethod "querySelector" #[toJS "inkproof-replacing-chart"] Data then
    answerViews el base
  let mirror (event : String) (id : String) (text : Value → IO String) : IO Unit := do
    if let .ref out _ ← doc.callMethod "getElementById" #[toJS id] Data then
      let listener ← Function.ofSyncFn fun args => do
        if let some (Data.ref e _) := args[0]? then out.set "textContent" (← text (← e.get "detail" Value))
        return .undefined
      doc.callMethod "addEventListener" #[toJS event, toJS listener] Unit
  mirror "inkproof-view" "view" fun d => do
    let v ← viewOf d
    return s!"{v.x.start} {v.x.span} {v.y.start} {v.y.span}"
  mirror "inkproof-pointer" "reading" fun d => do
    let (x, y) ← pointerOf d
    return s!"{x} {y}"
  if let .ref el _ ← doc.callMethod "querySelector" #[toJS "inkproof-cached-chart"] Data then
    redrawOnRequest el cache
