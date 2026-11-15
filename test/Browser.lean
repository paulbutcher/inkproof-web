/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Axis.LabelLayout
import Inkproof.Web.Host.Chart
import Inkproof.Web.Host.Measure

open Lasm.JS Inkproof.Web.Host

/-- The command list from `src`, with Axis-laid-out labels over it, measured by the browser. -/
def labelledScene (src : String) : Async Scene := do
  let scene ← fetchScene src
  let texts := (List.range 10).map fun i => s!"label number {i}"
  let measure ← measurer "12px sans-serif" texts.toArray
  let positioned := texts.zipIdx.map fun (text, i) => (20 + 40 * i.toFloat, text)
  let layout := Inkproof.Axis.layoutLabels measure 4 positioned
  return { scene with labels := layout.kept.toArray.map fun (x, text) => { text, x, y := 100 } }

def main : IO Unit := do
  register "inkproof-chart"
  register "inkproof-labelled-chart" labelledScene
