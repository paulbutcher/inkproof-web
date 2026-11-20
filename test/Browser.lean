/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Axis.LabelLayout
import Inkproof.Web.Host.Axis
import Inkproof.Web.Host.Chart
import Inkproof.Web.Host.Measure
import Inkproof.Viewport.View

open Lasm.JS Inkproof.Web Inkproof.Web.Host

/-- The command list from `src`, with Axis-laid-out labels over it, measured by the browser. -/
def labelledScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let texts := (List.range 10).map fun i => s!"label number {i}"
  let measure ← measurer "12px sans-serif" texts.toArray
  let positioned := texts.zipIdx.map fun (text, i) => (20 + 40 * i.toFloat, text)
  let layout := Inkproof.Axis.layoutLabels measure 4 positioned
  return { scene with labels := layout.kept.toArray.map fun (x, text) => { text, x, y := 100 } }

/-- The same text twice: centred on its anchor, and as Scene's vertical label under a bottom axis, a quarter turn anticlockwise with its end at the anchor. -/
def turnedScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let text := "turned label"
  return { scene with labels := #[
    { text, x := 100, y := 100, align := .center, baseline := .middle },
    Label.ofPlaced .bottom ⟨text, ⟨300, 100⟩, .vertical⟩] }

/-- A scene with two series of five points, a view over 0 to 100 (400 pixels across and 200 high), and data for the table. -/
def accessibleScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let axis : Inkproof.Viewport.Interval.Config Float :=
    { length := 400, minSpan := 1, maxSpan := 100, home := ⟨0, 100⟩, keyZoom := 2, keyPan := 0.25 }
  return { scene with access :=
    { name := "Sales", series := #["North", "South"], points := 5, view := some ⟨axis, { axis with length := 200 }⟩,
      header := #["Month", "North", "South"],
      rows := #[#["Jan", "1", "2"], #["Feb", "3", "4"]] } }

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

def main : IO Unit := do
  register "inkproof-accessible-chart" accessibleScene
  let base ← IO.mkRef none
  register "inkproof-replacing-chart" fun src => do
    let scene ← accessibleScene src
    base.set (some scene)
    return scene
  register "inkproof-chart"
  register "inkproof-labelled-chart" labelledScene
  register "inkproof-turned-chart" turnedScene
  let doc ← (← global).get "document"
  if let .ref el _ ← doc.callMethod "querySelector" #[toJS "inkproof-replacing-chart"] Data then
    answerViews el base
