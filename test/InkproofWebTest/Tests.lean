/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web
import Inkproof.Core
import InkproofTools.Test.Harness

namespace InkproofWebTest
open Inkproof.Web Inkproof.Core InkproofTools.Test

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

/-- A range touches only the tiles that hold it, each fetched once, and control is yielded once per tile. -/
def tilesCase : TestCase :=
  .mk "a tile query fetches only the tiles it touches" <|
    forAll 200 (fun g =>
        let (n, g) := g.below 6
        let (lo, g) := g.below 40
        let (len, g) := g.below 40
        ((n, lo, lo + len), g))
      fun (k, lo, hi) =>
        let n := k + 1
        let fetch (t : Nat) : StateM (List Nat × Nat) (Array (Total Nat)) :=
          modifyGet fun (seen, y) => (Array.range n |>.map fun j => ⟨t * n + j⟩, (t :: seen, y))
        let yield : StateM (List Nat × Nat) Unit := modify fun (seen, y) => (seen, y + 1)
        let (total, seen, yields) := match (foldTilesM n (Nat.succ_pos k) fetch yield lo hi).run ([], 0) with
          | (r, (seen, y)) => (r, seen, y)
        let touched := if lo < hi then (hi - 1) / n + 1 - lo / n else 0
        check (seen.reverse == (List.range touched).map (· + lo / n) && yields == touched
            && total.get == (List.range (hi - lo)).foldl (fun a i => a + lo + i) 0)
          s!"n={n} lo={lo} hi={hi} fetched {seen.reverse}, yielded {yields}, total {total.get}"

def tests : List TestCase := [sizingCase, cacheCase, unmeasuredCase, logCase, attrCase, tilesCase]

end InkproofWebTest
