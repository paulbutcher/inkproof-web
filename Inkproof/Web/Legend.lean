/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Access

namespace Inkproof.Web

open Inkproof.Float

/-- One legend entry: a series with its colour, whether it is hidden, and its value, at the cursor or, when `last`, at the end of the series. -/
structure LegendRow where
  name : String
  color : String
  hidden : Bool
  value : Option Float
  last : Bool

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

/-- The rows for `traces` with the cursor at data position `x`; with none each shows its series' last value. -/
def rows (traces : Array Trace) (x : Option Float) : Array LegendRow :=
  traces.map fun t =>
    { name := t.name, color := t.color, hidden := t.hidden, value := x.elim t.ys.back? t.valueAt, last := x.isNone }

/-- What a row reads as: its name, then its value or a dash, marked when it is the last value. -/
def text (r : LegendRow) : String :=
  s!"{r.name}: {(r.value.map showFloat).getD "-"}{if r.last then " (last)" else ""}"

/-- What the cursor readout says: the x position, and the y position when the pointer is over the chart. -/
def readout (x : Float) (y : Option Float) : String :=
  match y with
  | some y => s!"x: {showFloat x}, y: {showFloat y}"
  | none => s!"x: {showFloat x}"

theorem readout_eq (x : Float) (y : Option Float) :
    readout x y = match y with
      | some y => s!"x: {showFloat x}, y: {showFloat y}"
      | none => s!"x: {showFloat x}" := rfl

theorem rows_size (traces : Array Trace) (x : Option Float) : (rows traces x).size = traces.size := by
  simp [rows]

theorem rows_getElem? (traces : Array Trace) (x : Option Float) (i : Nat) :
    (rows traces x)[i]? =
      traces[i]?.map fun t =>
        { name := t.name, color := t.color, hidden := t.hidden, value := x.elim t.ys.back? t.valueAt, last := x.isNone } := by
  simp [rows]

theorem rows_last (traces : Array Trace) : ∀ r ∈ rows traces none, r.last = true := by
  simp [rows]

theorem text_eq (r : LegendRow) :
    text r = s!"{r.name}: {(r.value.map showFloat).getD "-"}{if r.last then " (last)" else ""}" := rfl

/-- Where the legend sits: over the plot at its top right, or below the plot at the right, in room of its own. -/
inductive Placement where
  | overlay
  | below
  deriving DecidableEq, Repr

/-- Validate the raw `legend` attribute: present (empty or `on`) overlays the plot, `bottom` goes below it, a missing one or `off` shows none. -/
def parsePlacement : Option String → Except String (Option Placement)
  | none | some "off" => .ok none
  | some "" | some "on" => .ok (some .overlay)
  | some "bottom" => .ok (some .below)
  | some s => .error s!"attribute legend is \"{s}\", expected on, bottom or off"

theorem parsePlacement_bottom : parsePlacement (some "bottom") = .ok (some .below) := rfl

theorem parsePlacement_none : parsePlacement none = .ok none := rfl

theorem parsePlacement_empty : parsePlacement (some "") = .ok (some .overlay) := rfl

theorem parsePlacement_on : parsePlacement (some "on") = .ok (some .overlay) := rfl

theorem parsePlacement_off : parsePlacement (some "off") = .ok none := rfl

theorem parsePlacement_other (s : String) (h1 : s ≠ "") (h2 : s ≠ "on") (h3 : s ≠ "off") (h4 : s ≠ "bottom") :
    parsePlacement (some s) = .error s!"attribute legend is \"{s}\", expected on, bottom or off" := by
  unfold parsePlacement
  split <;> simp_all

/-- Whether the raw `legend` attribute shows a legend. -/
def parse (raw : Option String) : Except String Bool :=
  (parsePlacement raw).map (·.isSome)

theorem parse_none : parse none = .ok false := rfl

theorem parse_empty : parse (some "") = .ok true := rfl

theorem parse_bottom : parse (some "bottom") = .ok true := rfl

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
