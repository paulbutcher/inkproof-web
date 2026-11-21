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

/-- The point of the trace nearest `x` along x, among all its points with a position, whether or not its value is missing. -/
def nearestPoint (t : Trace) (x : Float) : Option (Float × Float) :=
  (t.xs.zip t.ys).foldl (init := none) fun acc p =>
    if p.1.isNaN then acc
    else match acc with
      | none => some p
      | some b => if (p.1 - x).abs < (b.1 - x).abs then some p else acc

private theorem nearestStep_pos (x : Float) (l : List (Float × Float)) (init : Option (Float × Float))
    (hi : ∀ b, init = some b → b.1.isNaN = false) (b : Float × Float)
    (h : l.foldl (fun acc p =>
      if p.1.isNaN then acc
      else match acc with
        | none => some p
        | some b => if (p.1 - x).abs < (b.1 - x).abs then some p else acc) init = some b) :
    b.1.isNaN = false := by
  induction l generalizing init with
  | nil => exact hi b h
  | cons p l ih =>
    refine ih _ ?_ h
    intro c hc
    simp only at hc
    split at hc
    · exact hi c hc
    · rename_i hp
      cases init with
      | none => simp at hc; subst hc; simpa using hp
      | some d =>
        simp only at hc
        split at hc
        · simp at hc; subst hc; simpa using hp
        · exact hi c hc

private theorem nearestFold_mem (x : Float) (l : List (Float × Float)) (init : Option (Float × Float))
    (b : Float × Float)
    (h : l.foldl (fun acc p =>
      if p.1.isNaN then acc
      else match acc with
        | none => some p
        | some b => if (p.1 - x).abs < (b.1 - x).abs then some p else acc) init = some b) :
    b ∈ l ∨ init = some b := by
  induction l generalizing init with
  | nil => exact Or.inr h
  | cons p l ih =>
    rcases ih _ h with hm | hm
    · exact Or.inl (List.mem_cons_of_mem _ hm)
    · simp only at hm
      split at hm
      · exact Or.inr hm
      · cases init with
        | none => simp at hm; subst hm; exact Or.inl (List.mem_cons_self ..)
        | some d =>
          simp only at hm
          split at hm
          · simp at hm; subst hm; exact Or.inl (List.mem_cons_self ..)
          · exact Or.inr hm

/-- The point found by `nearestPoint` is one of the trace's points. The further claim that no other point with a position is strictly nearer is not stated: `Float` has no order lemmas, so the fold's comparisons cannot be chained. -/
theorem nearestPoint_mem (t : Trace) (x : Float) (p : Float × Float) (h : t.nearestPoint x = some p) :
    p ∈ (t.xs.zip t.ys).toList := by
  have := nearestFold_mem x (t.xs.zip t.ys).toList none p (by
    unfold nearestPoint at h; rw [← Array.foldl_toList] at h; exact h)
  simpa using this

/-- The point found by `nearestPoint` has a position. -/
theorem nearestPoint_not_nan (t : Trace) (x : Float) (p : Float × Float) (h : t.nearestPoint x = some p) :
    p.1.isNaN = false :=
  nearestStep_pos x (t.xs.zip t.ys).toList none (by simp) p (by
    unfold nearestPoint at h; rw [← Array.foldl_toList] at h; exact h)

/-- The value at the point nearest `x` along x; none when that point's value is missing. -/
def valueAt (t : Trace) (x : Float) : Option Float :=
  (t.nearestPoint x).bind fun p => if p.2.isNaN then none else some p.2

theorem valueAt_eq (t : Trace) (x : Float) :
    t.valueAt x = (t.nearestPoint x).bind fun p => if p.2.isNaN then none else some p.2 := rfl

theorem valueAt_not_nan (t : Trace) (x v : Float) (h : t.valueAt x = some v) : v.isNaN = false := by
  unfold valueAt at h
  cases hn : t.nearestPoint x with
  | none => simp [hn] at h
  | some p => simp only [hn, Option.bind_some] at h; split at h <;> simp_all

/-- The last value of the trace, none when it is missing. -/
def lastValue (t : Trace) : Option Float :=
  t.ys.back?.bind fun y => if y.isNaN then none else some y

theorem lastValue_eq (t : Trace) :
    t.lastValue = t.ys.back?.bind fun y => if y.isNaN then none else some y := rfl

theorem lastValue_not_nan (t : Trace) (v : Float) (h : t.lastValue = some v) : v.isNaN = false := by
  unfold lastValue at h
  cases hb : t.ys.back? with
  | none => simp [hb] at h
  | some y => simp only [hb, Option.bind_some] at h; split at h <;> simp_all

end Trace

namespace Legend

/-- The rows for `traces` with the cursor at data position `x`; with none each shows its series' last value. -/
def rows (traces : Array Trace) (x : Option Float) : Array LegendRow :=
  traces.map fun t =>
    { name := t.name, color := t.color, hidden := t.hidden, value := x.elim t.lastValue t.valueAt, last := x.isNone }

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
        { name := t.name, color := t.color, hidden := t.hidden, value := x.elim t.lastValue t.valueAt, last := x.isNone } := by
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

/-- A legend's placement, and whether its entries show values (`live`) or only each series' colour and name. -/
structure Style where
  placement : Placement
  live : Bool
  deriving DecidableEq, Repr

/-- Validate the raw `legend` attribute: a missing one or `off` shows none; `on` (or empty) overlays the plot, `bottom` goes below it and `static` leaves out the values, and `static` combines with either placement, as `static bottom`. -/
def parseStyle : Option String → Except String (Option Style)
  | none | some "off" => .ok none
  | some "" | some "on" => .ok (some { placement := .overlay, live := true })
  | some "bottom" => .ok (some { placement := .below, live := true })
  | some "static" | some "on static" | some "static on" => .ok (some { placement := .overlay, live := false })
  | some "static bottom" | some "bottom static" => .ok (some { placement := .below, live := false })
  | some s => .error s!"attribute legend is \"{s}\", expected on, bottom, static, static bottom or off"

theorem parseStyle_none : parseStyle none = .ok none := rfl

theorem parseStyle_off : parseStyle (some "off") = .ok none := rfl

theorem parseStyle_empty : parseStyle (some "") = .ok (some { placement := .overlay, live := true }) := by
  rfl

theorem parseStyle_on : parseStyle (some "on") = .ok (some { placement := .overlay, live := true }) := by
  rfl

theorem parseStyle_bottom : parseStyle (some "bottom") = .ok (some { placement := .below, live := true }) := by
  rfl

theorem parseStyle_static : parseStyle (some "static") = .ok (some { placement := .overlay, live := false }) := by
  rfl

theorem parseStyle_static_bottom :
    parseStyle (some "static bottom") = .ok (some { placement := .below, live := false }) := by
  rfl

theorem parseStyle_on_static :
    parseStyle (some "on static") = .ok (some { placement := .overlay, live := false }) := by
  rfl

theorem parseStyle_static_on :
    parseStyle (some "static on") = .ok (some { placement := .overlay, live := false }) := by
  rfl

theorem parseStyle_bottom_static :
    parseStyle (some "bottom static") = .ok (some { placement := .below, live := false }) := by
  rfl

theorem parseStyle_other (s : String) (h1 : s ≠ "") (h2 : s ≠ "on") (h3 : s ≠ "off") (h4 : s ≠ "bottom")
    (h5 : s ≠ "static") (h6 : s ≠ "on static") (h7 : s ≠ "static on") (h8 : s ≠ "static bottom")
    (h9 : s ≠ "bottom static") :
    parseStyle (some s) = .error s!"attribute legend is \"{s}\", expected on, bottom, static, static bottom or off" := by
  unfold parseStyle
  split <;> simp_all

/-- Whether the raw `legend` attribute shows a legend. -/
def parse (raw : Option String) : Except String Bool :=
  (parseStyle raw).map (·.isSome)

theorem parse_none : parse none = .ok false := rfl

theorem parse_empty : parse (some "") = .ok true := by
  rfl

theorem parse_bottom : parse (some "bottom") = .ok true := by
  rfl

/-- Whether the raw `legend` attribute asks for the values: false for `static`, and for no legend. -/
def live (raw : Option String) : Bool :=
  match parseStyle raw with
  | .ok (some s) => s.live
  | _ => false

theorem live_of_style (raw : Option String) (s : Style) (h : parseStyle raw = .ok (some s)) :
    live raw = s.live := by
  simp [live, h]

theorem live_of_none (raw : Option String) (h : parseStyle raw = .ok none) : live raw = false := by
  simp [live, h]

theorem live_of_error (raw : Option String) (e : String) (h : parseStyle raw = .error e) : live raw = false := by
  simp [live, h]

theorem live_static : live (some "static bottom") = false := by
  rfl

theorem live_on : live (some "on") = true := by
  rfl

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
