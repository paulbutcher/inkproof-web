/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Access

namespace Inkproof.Web

open Inkproof.Float

/-- One legend entry: a series with its colour, whether it is hidden, and its value at the cursor. -/
structure LegendRow where
  name : String
  color : String
  hidden : Bool
  value : Option Float

namespace Trace

/-- The value of the trace at the point nearest `x` along x, if it has one. -/
def valueAt (t : Trace) (x : Float) : Option Float :=
  (Nearest.find .x #[{ t with hidden := false }] x 0).map (·.y)

theorem valueAt_eq (t : Trace) (x : Float) :
    t.valueAt x = (Nearest.find .x #[{ t with hidden := false }] x 0).map (·.y) := rfl

theorem valueAt_none_iff (t : Trace) (x : Float) :
    t.valueAt x = none ↔ Nearest.candidates #[{ t with hidden := false }] = [] := by
  simp [valueAt, Nearest.find_none_iff]

end Trace

namespace Legend

/-- The rows for `traces` with the cursor at data position `x`; none shows no values. -/
def rows (traces : Array Trace) (x : Option Float) : Array LegendRow :=
  traces.map fun t => { name := t.name, color := t.color, hidden := t.hidden, value := x.bind t.valueAt }

/-- What a row reads as: its name, then its value or a dash. -/
def text (r : LegendRow) : String :=
  s!"{r.name}: {(r.value.map showFloat).getD "-"}"

theorem rows_size (traces : Array Trace) (x : Option Float) : (rows traces x).size = traces.size := by
  simp [rows]

theorem rows_getElem? (traces : Array Trace) (x : Option Float) (i : Nat) :
    (rows traces x)[i]? =
      traces[i]?.map fun t => { name := t.name, color := t.color, hidden := t.hidden, value := x.bind t.valueAt } := by
  simp [rows]

theorem rows_value_none (traces : Array Trace) : ∀ r ∈ rows traces none, r.value = none := by
  simp [rows]

theorem text_eq (r : LegendRow) : text r = s!"{r.name}: {(r.value.map showFloat).getD "-"}" := rfl

/-- Validate the raw `legend` attribute: present (empty or `on`) shows the legend, a missing one or `off` does not. -/
def parse : Option String → Except String Bool
  | none | some "off" => .ok false
  | some "" | some "on" => .ok true
  | some s => .error s!"attribute legend is \"{s}\", expected on or off"

theorem parse_none : parse none = .ok false := rfl

theorem parse_empty : parse (some "") = .ok true := rfl

/-- What a tooltip at `c` reads: the series and the point's position, from the traces `c` was found in. -/
def tooltip (traces : Array Trace) (c : Candidate) : Option String := do
  let t ← traces[c.series]?
  let x ← t.xs[c.point]?
  let y ← t.ys[c.point]?
  some s!"{t.name}: {showFloat x}, {showFloat y}"

theorem tooltip_eq (traces : Array Trace) (c : Candidate) (t : Trace) (x y : Float)
    (ht : traces[c.series]? = some t) (hx : t.xs[c.point]? = some x) (hy : t.ys[c.point]? = some y) :
    tooltip traces c = some s!"{t.name}: {showFloat x}, {showFloat y}" := by
  simp [tooltip, ht, hx, hy]

/-- The traces with series `i` hidden if it was shown and shown if it was hidden. -/
def toggle (traces : Array Trace) (i : Nat) : Array Trace :=
  traces.modify i fun t => { t with hidden := !t.hidden }

theorem toggle_size (traces : Array Trace) (i : Nat) : (toggle traces i).size = traces.size := by
  simp [toggle]

theorem toggle_hidden (traces : Array Trace) (i : Nat) :
    (toggle traces i)[i]?.map (·.hidden) = traces[i]?.map (!·.hidden) := by
  simp only [toggle, Array.getElem?_modify]
  split <;> simp_all <;> rfl

end Legend

end Inkproof.Web
