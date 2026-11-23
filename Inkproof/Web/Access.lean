/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Axis.NumberFormat
import Inkproof.Core.Proofs.Decimal
import Inkproof.Float.RatLemmas
import Inkproof.Viewport.View
import Inkproof.Web.Probe

namespace Inkproof.Web

open Inkproof.Viewport

/-- What a key asks of a chart. Zoom and pan are Viewport's own keys, so a key and a pointer gesture reach the view through the same `View.step`. -/
inductive Command where
  | view (k : Key)
  | cursorLeft
  | cursorRight
  | cursorFirst
  | cursorLast
  | nextSeries
  | previousSeries
  | reset
  deriving DecidableEq, Repr

namespace Command

/-- The command for a DOM `KeyboardEvent.key`, with whether shift was held. Arrows pan, shifted arrows move the cursor, `+` and `-` zoom, Home and End jump the cursor, Page Down and Page Up select the series, and `0` or Escape resets. -/
def ofKey (key : String) (shift : Bool) : Option Command :=
  match key, shift with
  | "ArrowLeft", false => some (.view .left)
  | "ArrowRight", false => some (.view .right)
  | "ArrowUp", false => some (.view .up)
  | "ArrowDown", false => some (.view .down)
  | "ArrowLeft", true => some .cursorLeft
  | "ArrowRight", true => some .cursorRight
  | "+", _ | "=", _ => some (.view .zoomIn)
  | "-", _ | "_", _ => some (.view .zoomOut)
  | "Home", _ => some .cursorFirst
  | "End", _ => some .cursorLast
  | "PageDown", _ => some .nextSeries
  | "PageUp", _ => some .previousSeries
  | "0", _ | "Escape", _ => some .reset
  | _, _ => none

/-- A shifted arrow moves the cursor and an unshifted one pans the view. -/
theorem ofKey_arrows :
    ofKey "ArrowLeft" true = some .cursorLeft ∧ ofKey "ArrowRight" true = some .cursorRight ∧
    ofKey "ArrowLeft" false = some (.view .left) ∧ ofKey "ArrowRight" false = some (.view .right) :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- Keys with no meaning for a chart, such as Tab, give no command, so the browser keeps them. -/
theorem ofKey_tab (shift : Bool) : ofKey "Tab" shift = none := by cases shift <;> rfl

end Command

/-- What a chart's keys act on: the view's configuration and the extent of the data. -/
structure NavConfig where
  view : ViewConfig Float
  points : Nat
  series : Nat

/-- The keyboard-driven state: the visible ranges, and the cursor's point and series. -/
structure Nav where
  view : View Float
  point : Nat := 0
  series : Nat := 0
  deriving BEq, Repr

namespace Nav

/-- The state a chart starts in. -/
def home (c : NavConfig) : Nav := { view := View.home c.view }

/-- The state after a command. The cursor stays on a point and the series cycles. -/
def apply (c : NavConfig) (n : Nav) : Command → Nav
  | .view k => { n with view := View.step c.view n.view (.key k) }
  | .cursorLeft => { n with point := n.point - 1 }
  | .cursorRight => { n with point := min (n.point + 1) (c.points - 1) }
  | .cursorFirst => { n with point := 0 }
  | .cursorLast => { n with point := c.points - 1 }
  | .nextSeries => { n with series := (n.series + 1) % c.series }
  | .previousSeries => { n with series := (n.series + c.series - 1) % c.series }
  | .reset => home c

/-- The state with its cursor moved back inside a chart of `points` points and `series` series. -/
def clamp (points series : Nat) (n : Nav) : Nav :=
  { n with point := Float.clamp 0 (points - 1) n.point, series := Float.clamp 0 (series - 1) n.series }

theorem clamp_of_lt (points series : Nat) (n : Nav) (hp : n.point < points) (hs : n.series < series) :
    clamp points series n = n := by
  simp only [clamp, Float.clamp]; congr 1 <;> (repeat split) <;> simp_all <;> omega

theorem clamp_view (points series : Nat) (n : Nav) : (clamp points series n).view = n.view := rfl

theorem clamp_point_lt (points series : Nat) (n : Nav) (h : 0 < points) : (clamp points series n).point < points := by
  simp only [clamp, Float.clamp]; (repeat split) <;> simp_all <;> (try split) <;> omega

theorem clamp_series_lt (points series : Nat) (n : Nav) (h : 0 < series) : (clamp points series n).series < series := by
  simp only [clamp, Float.clamp]; (repeat split) <;> simp_all <;> (try split) <;> omega

theorem home_view (c : NavConfig) : (home c).view = View.home c.view := rfl

theorem home_cursor (c : NavConfig) : (home c).point = 0 ∧ (home c).series = 0 := ⟨rfl, rfl⟩

theorem apply_view (c : NavConfig) (n : Nav) (k : Key) :
    (n.apply c (.view k)).view = View.step c.view n.view (.key k) := rfl

theorem apply_reset (c : NavConfig) (n : Nav) : n.apply c .reset = home c := rfl

theorem apply_point_lt (c : NavConfig) (n : Nav) (h : n.point < c.points) (cmd : Command) :
    (n.apply c cmd).point < c.points := by
  cases cmd <;> simp only [apply, home] <;> omega

theorem apply_series_lt (c : NavConfig) (n : Nav) (h : n.series < c.series) (cmd : Command) :
    (n.apply c cmd).series < c.series := by
  cases cmd <;> simp only [apply, home]
  · exact h
  all_goals first | omega | exact Nat.mod_lt _ (by omega)

end Nav

/-- The text a chart exposes to assistive technology. -/
structure Access where
  name : String := "Chart"
  series : Array String := #[]
  points : Nat := 0
  /-- Replaces the generated summary. -/
  summary : Option String := none
  header : Array String := #[]
  rows : Array (Array String) := #[]
  /-- Without it the chart has no view for keys to change. -/
  view : Option (ViewConfig Float) := none
  /-- Where the plot's top left lies in the element, in CSS pixels; its size is the view configuration's two lengths. Pointer positions are taken from here. -/
  plotOrigin : Float × Float := (0, 0)
  /-- The series' points, which the tooltip and legend read; without them a chart has neither. -/
  traces : Array Trace := #[]
  /-- Groups of named values per x, which the legend shows beside the series. -/
  groups : Array ValueGroup := #[]

/-- A number as people write it: no trailing zeros, and no point on a whole number. -/
def showFloat (f : Float) : String := String.ofList (Inkproof.Core.Decimal.trimZeros (toString f).toList)

theorem showFloat_eq (f : Float) (w fr : List Char) (hw : '.' ∉ w) (h : (toString f).toList = w ++ '.' :: fr) :
    showFloat f = String.ofList (if (Inkproof.Core.Decimal.trimFrac fr).isEmpty then w
      else w ++ '.' :: Inkproof.Core.Decimal.trimFrac fr) := by
  simp [showFloat, h, Inkproof.Core.Decimal.trimZeros_spec w fr hw]

theorem showFloat_of_not_mem (f : Float) (h : '.' ∉ (toString f).toList) : showFloat f = toString f := by
  simp [showFloat, Inkproof.Core.Decimal.trimZeros_of_not_mem _ h]

/-- `x` as the format writes it; with no format, or for a value it cannot write such as NaN or an infinity, as `showFloat` does. -/
def showNumber (fmt : Option Inkproof.Axis.NumberFormat) (x : Float) : String :=
  (fmt.bind (·.format x)).getD (showFloat x)

theorem showNumber_eq (fmt : Option Inkproof.Axis.NumberFormat) (x : Float) :
    showNumber fmt x = (fmt.bind (·.format x)).getD (showFloat x) := rfl

/-- A summary from the chart's name, series and visible x range. -/
def describe (name : String) (series : Array String) (xStart xEnd : Float) : String :=
  let names := ", ".intercalate series.toList
  s!"{name}: {series.size} series ({names}), showing {showFloat xStart} to {showFloat xEnd}"

theorem describe_eq (name : String) (series : Array String) (xStart xEnd : Float) :
    describe name series xStart xEnd =
      s!"{name}: {series.size} series ({", ".intercalate series.toList}), showing {showFloat xStart} to {showFloat xEnd}" := rfl

namespace Access

/-- The summary shown for `view`: the application's own if it gave one. -/
def summaryText (a : Access) (view : Option (View Float)) : String :=
  match a.summary, view with
  | some s, _ => s
  | none, some v => describe a.name a.series v.x.start (v.x.start + v.x.span)
  | none, none => s!"{a.name}: {a.series.size} series"

theorem summaryText_some (a : Access) (s : String) (v : Option (View Float)) (h : a.summary = some s) :
    a.summaryText v = s := by simp [summaryText, h]

/-- What a cursor announces: its series and its place among the points. -/
def cursorText (a : Access) (n : Nav) : String :=
  let series := (a.series[n.series]?).getD s!"series {n.series + 1}"
  s!"{series}, point {n.point + 1} of {a.points}"

theorem cursorText_eq (a : Access) (n : Nav) :
    a.cursorText n =
      s!"{(a.series[n.series]?).getD s!"series {n.series + 1}"}, point {n.point + 1} of {a.points}" := rfl

end Access

end Inkproof.Web
