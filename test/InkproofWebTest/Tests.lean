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

def interactionErrorCase : TestCase :=
  .mk "conflicting, unknown and zero interaction words are reported" do
    let bad (v : String) := match Interaction.parse (some v) with | .error _ => true | .ok _ => false
    check (bad "wheel-zoom no-wheel" && bad "no-drag no-drag" && bad "drag-pan sideways" && bad "0px" && bad "4")
      "a bad interaction was accepted"

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
    let at8 := (Legend.groupRows g (some 8)).map (Legend.text none)
    let last := (Legend.groupRows g none).map (Legend.text none)
    check (at8 == #["a: idle", "b: off"] && last == #["a: idle (last)", "b: off (last)"] &&
        (Legend.groupRows g (some 1)).map (Legend.text none) == #["a: on", "b: -"])
      s!"{at8} {last}"

/-- Two series over a 400 by 200 pixel plot of 0 to 100 by 0 to 100: the first has a value at x of 25, the second a gap. -/
def markerTraces : Array Trace :=
  let nan := 0.0 / 0.0
  #[{ name := "a", color := "#d33", xs := #[0, 25, 50], ys := #[10, 30, 20] },
    { name := "b", color := "#36c", xs := #[0, 25, 50], ys := #[80, nan, 90], hollow := true }]

def markerConfig : Inkproof.Viewport.ViewConfig Float :=
  let axis : Inkproof.Viewport.Interval.Config Float :=
    { length := 400, minSpan := 1, maxSpan := 100, home := ⟨0, 100⟩, keyZoom := 2, keyPan := 0.25 }
  ⟨axis, { axis with length := 200 }⟩

/-- A series with a value at the cursor's x gets a marker at that value's projected position, one with a gap gets none, and the mode off gets none. -/
def markerCase : TestCase :=
  .mk "a marker sits at each series' value at the cursor, and not over a gap" do
    let view := Inkproof.Viewport.View.home markerConfig
    let all := Markers.atCursor .all {} markerConfig view markerTraces 25 none
    let off := Markers.atCursor .off {} markerConfig view markerTraces 25 none
    let hidden := Markers.atCursor .all {} markerConfig view (markerTraces.map fun t => { t with hidden := true }) 25 none
    let zoomed := Markers.atCursor .all {} markerConfig { view with x := ⟨0, 50⟩ } markerTraces 25 none
    let at0 (ms : Array Marker) := ms[0]?.map fun m => (m.series, m.x, m.y, m.color)
    check (all.size == 1 && at0 all == some (0, 100, 140, "#d33") && off.isEmpty && hidden.isEmpty &&
        (at0 zoomed).map (·.2.1) == some 200)
      s!"{at0 all} {off.size} {hidden.size} {at0 zoomed}"

/-- A series drawn with hollow markers gets a filled one even when the style is an outline. -/
def markerHollowCase : TestCase :=
  .mk "a hollow series gets a filled marker under the cursor" do
    let view := Inkproof.Viewport.View.home markerConfig
    let t : Trace := { name := "b", color := "#36c", xs := #[0, 25], ys := #[80, 70], hollow := true }
    let plain : Trace := { t with hollow := false }
    let style : MarkerStyle := { filled := false }
    let f (t : Trace) := (Markers.atCursor .all style markerConfig view #[t] 25 none)[0]?.map (·.filled)
    check (f t == some true && f plain == some false) s!"{f t} {f plain}"

/-- With the pointer's y known, the nearest marker is that of the series nearest it; without, the first nearest along x. -/
def markerNearestCase : TestCase :=
  .mk "the nearest marker is that of the series nearest the pointer" do
    let view := Inkproof.Viewport.View.home markerConfig
    let ts : Array Trace := #[
      { name := "a", color := "#d33", xs := #[25], ys := #[30] },
      { name := "b", color := "#36c", xs := #[25], ys := #[70] }]
    let near (y : Option Float) := (Markers.atCursor .nearest {} markerConfig view ts 25 y).map (·.series)
    check (near (some 65) == #[1] && near (some 35) == #[0] && near none == #[0]) s!"{near (some 65)} {near (some 35)} {near none}"

/-- Bubbles as traces with sizes and labels: for any pointer, the tooltip names the visible bubble nearest its centre, with its label and size. -/
def bubbleCase : TestCase :=
  .mk "the tooltip names the visible bubble nearest the pointer" do
    let ts : Array Trace := #[
      { name := "A", color := "#d33", xs := #[10, 40, 70], ys := #[20, 80, 50], sizes := #[1, 2, 3], labels := #["p", "q", "r"] },
      { name := "B", color := "#36c", xs := #[15, 55], ys := #[25, 45], sizes := #[4, 5], labels := #["s", "t"] },
      { name := "C", color := "#3a3", xs := #[12], ys := #[22], sizes := #[9], labels := #["hidden"], hidden := true }]
    forAll 200 (fun g =>
        let (x, g) := g.below 100
        let (y, g) := g.below 100
        ((x.toFloat, y.toFloat), g))
      fun (px, py) =>
        match Nearest.find .plane ts px py with
        | none => check false "no bubble found"
        | some hit =>
          let d (c : Candidate) := Metric.dist .plane px py c
          let least := (Nearest.candidates ts).all fun c => d hit ≤ d c
          let text := (Tooltip.single none true ts hit).getD ""
          match ts[hit.series]? with
          | none => check false "no series"
          | some t =>
            match t.labels[hit.point]?, t.sizes[hit.point]? with
            | some l, some z =>
              check (least && !(hit.series == 2) && text.startsWith s!"{t.name}, {l}: " &&
                text.endsWith (showFloat z)) s!"{px} {py} {text}"
            | _, _ => check false "no label or size"

def facetSizeCase : TestCase :=
  .mk "pixel words set the marker size and the least box drag" do
    let marker := match CursorStyle.parse (some "markers 10px outline") with
      | .ok c => c.marker.size == 10 && !c.marker.filled && c.markers == .all
      | .error _ => false
    let box := match Interaction.parse (some "drag-box 12px box-y") with
      | .ok i => i.box.minDistance == 12 && (match i.box.axes with | .y => true | _ => false) && i.drag == .box
      | .error _ => false
    check (marker && box) s!"marker {marker} box {box}"

def cursorErrorCase : TestCase :=
  .mk "conflicting, unknown and zero cursor words are reported" do
    let bad (v : String) := match CursorStyle.parse (some v) with | .error _ => true | .ok _ => false
    check (bad "x xy" && bad "markers nearest-marker" && bad "filled outline" && bad "6px 8px" && bad "0px" && bad "hollow")
      "a bad cursor was accepted"

def numberFormatCase : TestCase :=
  .mk "number-format words change how legend and readout numbers are written" do
    let fmt (v : String) := match Numbers.parse (some v) with | .ok f => f | .error _ => none
    let bad (v : String) := match Numbers.parse (some v) with | .error _ => true | .ok _ => false
    let big := showNumber (fmt "compact 1dp") 1234567
    let de := showNumber (fmt "de 2dp") 1234.5
    let row : LegendRow := { name := "n", color := "#000", hidden := false, value := some 1500, last := false }
    check (big == "1.2M" && de == "1.234,50" && Legend.text (fmt "compact") row == "n: 1.5k" &&
        showNumber none (0.0 / 0.0) == showFloat (0.0 / 0.0) &&
        bad "de fr" && bad "2dp 3dp" && bad "compact compact" && bad "pretty")
      s!"{big} {de} {Legend.text (fmt "compact") row}"

def showFloatCase : TestCase :=
  .mk "showFloat drops trailing zeros and a bare point" do
    let got := [0.0, 1.5, 100.0, 0.000001, 0.0 / 0.0, 1.0 / 0.0].map showFloat
    check (got == ["0", "1.5", "100", "0.000001", "NaN", "inf"]) s!"{got}"

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
  [bubbleCase, markerCase, markerHollowCase, markerNearestCase, cursorErrorCase, tooltipPlaceCase, tooltipParseCase, legendWordsCase, sizingCase, cacheCase, unmeasuredCase, logCase, attrCase, interactionErrorCase, facetSizeCase, legendGapCase, numberFormatCase, showFloatCase]

end InkproofWebTest
