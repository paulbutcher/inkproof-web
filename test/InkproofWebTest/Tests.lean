/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web
import InkproofTools.Test.Harness

namespace InkproofWebTest
open Inkproof.Web InkproofTools.Test

/-- A surface sized for an element never needs resizing for that same element. -/
def sizingCase : TestCase :=
  .mk "a surface sized for an element does not need resizing" <|
    forAll 200 (fun g =>
        let (w, g) := g.below 4000
        let (h, g) := g.below 4000
        let (r, g) := g.below 4000
        ((w, h, r), g))
      fun (w, h, r) =>
        check (!(Size.backing w h r).needsResize w h r) s!"{w} {h} {r}"

/-- However many times a text is asked for, it is measured once. -/
def cacheCase : TestCase :=
  .mk "cached text is measured once" do
    let measure (_ _ : String) : StateM Nat (Float × Float) := modifyGet fun n => ((1.0, 2.0), n + 1)
    let run : StateM Nat (Float × Float) := do
      let (_, c) ← TextCache.empty.getOrMeasure "12px serif" "abc" measure
      let (size, c) ← c.getOrMeasure "12px serif" "abc" measure
      let (_, c) ← c.getOrMeasure "12px serif" "abcd" measure
      let (_, _) ← c.getOrMeasure "bold 12px serif" "abc" measure
      return size
    let (size, taken) := run.run 0
    check (taken == 3 && size == (1.0, 2.0)) s!"{taken} measurements, size {size}"

/-- Text that was never measured is not a number, so Axis drops it. -/
def unmeasuredCase : TestCase :=
  .mk "unmeasured text is not a number" do
    let (w, h) := TextCache.empty.measurer "12px serif" "abc"
    check (w.isNaN && h.isNaN) s!"{w} {h}"

def logCase : TestCase :=
  .mk "a console line names the values that decided it" do
    let line := formatLine .warn "context lost" [("charts", "3"), ("reason", "gpu reset")]
    check (line == "[inkproof warn] context lost charts=3 reason=gpu reset") line

def attrCase : TestCase :=
  .mk "an unknown log level is an error" <|
    forAll 100 (fun g => let (n, g) := g.below 1000; (s!"level{n}", g)) fun s =>
      match ChartAttrs.parse (some "chart.bin") (some s) with
      | .error _ => .ok ()
      | .ok a => .error s!"accepted {repr a}"

def tests : List TestCase := [sizingCase, cacheCase, unmeasuredCase, logCase, attrCase]

end InkproofWebTest
