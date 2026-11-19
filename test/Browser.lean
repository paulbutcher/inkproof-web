/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Axis.LabelLayout
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

/-- The same text twice: centred on its anchor, and turned a quarter turn anticlockwise with its end at the anchor. -/
def turnedScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let text := "turned label"
  return { scene with labels := #[
    { text, x := 100, y := 100, align := .center, baseline := .middle },
    { text, x := 300, y := 100, align := .end, baseline := .middle, rotation := -1.5707963267948966 }] }

/-- A scene with two series of five points, a view over 0 to 100 (400 pixels across and 200 high), and data for the table. -/
def accessibleScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let axis : Inkproof.Viewport.Interval.Config Float :=
    { length := 400, minSpan := 1, maxSpan := 100, home := ⟨0, 100⟩, keyZoom := 2, keyPan := 0.25 }
  return { scene with access :=
    { name := "Sales", series := #["North", "South"], points := 5, view := some ⟨axis, { axis with length := 200 }⟩,
      header := #["Month", "North", "South"],
      rows := #[#["Jan", "1", "2"], #["Feb", "3", "4"]] } }

def main : IO Unit := do
  register "inkproof-accessible-chart" accessibleScene
  register "inkproof-chart"
  register "inkproof-labelled-chart" labelledScene
  register "inkproof-turned-chart" turnedScene
