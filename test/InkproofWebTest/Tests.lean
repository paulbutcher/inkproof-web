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

open Inkproof.Viewport in
def plot : ViewConfig Float :=
  let axis : Interval.Config Float := ⟨300, 1, 1000, ⟨0, 100⟩, 2, 0.1⟩
  ⟨axis, axis⟩

def boxMinCase : TestCase :=
  .mk "a zero box-min is refused" do
    let zero := match BoxConfig.parse none (some "0") with | .error _ => true | .ok _ => false
    check zero "zero accepted"

def dragCase : TestCase :=
  .mk "an unknown drag value is refused" do
    let bad := match DragMode.parse (some "zoom") with | .error _ => true | .ok _ => false
    check bad "zoom accepted"

/-- A legend row over a missing value reads as a dash, never the value of a neighbouring point. -/
def legendGapCase : TestCase :=
  .mk "a legend value over a gap is missing" do
    let nan := 0.0 / 0.0
    let t : Trace := { name := "a", color := "#000", xs := #[0, 1, 2, 3], ys := #[5, nan, 7, nan] }
    let over := t.valueAt 1.1
    let beside := t.valueAt 2.1
    let last := Legend.rows #[t] none
    check (over.isNone && beside == some 7 && last.all (·.value.isNone))
      s!"{over} {beside} {last.map (·.value)}"

def legendWordsCase : TestCase :=
  .mk "a text group reads the state nearest the cursor" do
    let g : ValueGroup := {
      name := "g", color := "#000", labels := #["a", "b"], xs := #[0, 10]
      words := #[#[some "on", none], #[some "idle", some "off"]] }
    let at8 := (Legend.groupRows g (some 8)).map Legend.text
    let last := (Legend.groupRows g none).map Legend.text
    check (at8 == #["a: idle", "b: off"] && last == #["a: idle (last)", "b: off (last)"] &&
        (Legend.groupRows g (some 1)).map Legend.text == #["a: on", "b: -"])
      s!"{at8} {last}"

/-- Wherever the anchor and however far the offset, a tooltip that fits in the chart lies inside it. -/
def tooltipPlaceCase : TestCase :=
  .mk "a tooltip that fits in the chart is placed inside it" <|
    forAll 500 (fun g =>
        let (x, g) := g.below 500
        let (y, g) := g.below 300
        let (o, g) := g.below 400
        let (k, g) := g.below 4
        ((x, y, o, k), g))
      fun (x, y, o, k) =>
        let style : Tooltip.Style := { metric := .x, shared := false, showX := true, anchor := .point, right := k % 2 == 0, top := k < 2, offset := o }
        let (l, t) := style.place x.toFloat y.toFloat 90 20 400 200
        check (0 ≤ l && l + 90 ≤ 400 && 0 ≤ t && t + 20 ≤ 200) s!"{x} {y} {o} {k}: {l} {t}"

def tooltipParseCase : TestCase :=
  .mk "a tooltip attribute is refused when its words contradict each other" do
    let bad (s : String) := match Tooltip.parse (some s) with | .error _ => true | .ok _ => false
    let offset := match Tooltip.parse (some "xy pointer bottom-left 12") with
      | .ok (some s) => s.offset == 12 && s.anchor == .pointer && !s.top && !s.right && s.metric == .plane
      | _ => false
    check (bad "shared xy" && bad "x xy" && bad "top-left top-right" && bad "12 13" && bad "wide" && offset) "tooltip words"

def tests : List TestCase :=
  [tooltipPlaceCase, tooltipParseCase, legendWordsCase, sizingCase, cacheCase, unmeasuredCase, logCase, attrCase, boxMinCase, dragCase, legendGapCase]

end InkproofWebTest
