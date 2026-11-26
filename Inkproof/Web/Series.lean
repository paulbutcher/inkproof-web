/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

/-- What an `inkproof-series` event says: the legend entry clicked, and whether its series is now hidden. -/
structure SeriesEvent where
  series : Nat
  hidden : Bool
  deriving BEq, Repr

namespace SeriesEvent

/-- The event from its `detail`, whose series is a JavaScript number: none unless it is a natural number. -/
def decode (series : Float) (hidden : Bool) : Option SeriesEvent :=
  if series.isNaN || series < 0 || series.floor != series || 4503599627370496 < series then none
  else some { series := series.toUInt64.toNat, hidden }

theorem decode_eq (series : Float) (hidden : Bool) (e : SeriesEvent) (h : decode series hidden = some e) :
    e = { series := series.toUInt64.toNat, hidden } := by
  unfold decode at h
  split at h <;> simp_all

-- That `e.series.toFloat = series` is not provable: `Float.floor`, `Float.toUInt64` and `Nat.toFloat` are opaque, so the guard says nothing about the conversion.
theorem decode_hidden (series : Float) (hidden : Bool) (e : SeriesEvent) (h : decode series hidden = some e) : e.hidden = hidden := by
  unfold decode at h
  split at h <;> simp_all
  rw [← h]

end SeriesEvent

/-- The series a chart's legend has hidden, by index; one past the end is shown. -/
abbrev Hidden := Array Bool

namespace Hidden

/-- The hidden series after `e` on a chart of `count` series: the one `e` names is as it says; an index outside the chart changes nothing. -/
def apply (count : Nat) (off : Hidden) (e : SeriesEvent) : Hidden :=
  if e.series < count then (off ++ Array.replicate (e.series + 1 - off.size) false).set! e.series e.hidden else off

theorem apply_getD (count : Nat) (off : Hidden) (e : SeriesEvent) (i : Nat) :
    (apply count off e).getD i false = if i = e.series ∧ e.series < count then e.hidden else off.getD i false := by
  unfold apply
  by_cases hc : e.series < count
  · simp only [hc, ite_true, and_true]
    simp only [Array.getD_eq_getD_getElem?, Array.set!_eq_setIfInBounds, Array.getElem?_setIfInBounds, Array.getElem?_append,
      Array.size_append, Array.size_replicate, Array.getElem?_replicate]
    by_cases hi : i = e.series
    · subst hi
      have : e.series < off.size + (e.series + 1 - off.size) := by omega
      simp [this]
    · have hi' : e.series ≠ i := Ne.symm hi
      simp only [hi, hi', ite_false]
      by_cases h1 : i < off.size
      · simp [h1]
      · have : off.size ≤ i := by omega
        simp [h1]
        split <;> simp
  · simp [hc]

end Hidden

end Inkproof.Web
