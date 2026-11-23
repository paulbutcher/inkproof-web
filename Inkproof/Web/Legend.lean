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
  /-- A text read in place of `value`. -/
  word : Option String := none

/-- The entry of `ps` whose position is nearest `x`, among those with a position; the first of equally near ones. -/
def nearestBy {α : Type} (ps : Array (Float × α)) (x : Float) : Option (Float × α) :=
  ps.foldl (init := none) fun acc p =>
    if p.1.isNaN then acc
    else match acc with
      | none => some p
      | some b => if (p.1 - x).abs < (b.1 - x).abs then some p else acc

private theorem nearestStep_pos {α : Type} (x : Float) (l : List (Float × α)) (init : Option (Float × α))
    (hi : ∀ b, init = some b → b.1.isNaN = false) (b : Float × α)
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

private theorem nearestFold_mem {α : Type} (x : Float) (l : List (Float × α)) (init : Option (Float × α))
    (b : Float × α)
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

/-- The entry found by `nearestBy` is one of `ps`. The further claim that no other entry with a position is strictly nearer is not stated: `Float` has no order lemmas, so the fold's comparisons cannot be chained. -/
theorem nearestBy_mem {α : Type} (ps : Array (Float × α)) (x : Float) (p : Float × α)
    (h : nearestBy ps x = some p) : p ∈ ps.toList := by
  have := nearestFold_mem x ps.toList none p (by
    unfold nearestBy at h; rw [← Array.foldl_toList] at h; exact h)
  simpa using this

/-- The entry found by `nearestBy` has a position. -/
theorem nearestBy_not_nan {α : Type} (ps : Array (Float × α)) (x : Float) (p : Float × α)
    (h : nearestBy ps x = some p) : p.1.isNaN = false :=
  nearestStep_pos x ps.toList none (by simp) p (by
    unfold nearestBy at h; rw [← Array.foldl_toList] at h; exact h)

namespace Trace

/-- The point of the trace nearest `x` along x, among all its points with a position, whether or not its value is missing. -/
def nearestPoint (t : Trace) (x : Float) : Option (Float × Float) :=
  nearestBy (t.xs.zip t.ys) x

theorem nearestPoint_eq (t : Trace) (x : Float) : t.nearestPoint x = nearestBy (t.xs.zip t.ys) x := rfl

/-- The point found by `nearestPoint` is one of the trace's points. -/
theorem nearestPoint_mem (t : Trace) (x : Float) (p : Float × Float) (h : t.nearestPoint x = some p) :
    p ∈ (t.xs.zip t.ys).toList :=
  nearestBy_mem _ x p h

/-- The point found by `nearestPoint` has a position. -/
theorem nearestPoint_not_nan (t : Trace) (x : Float) (p : Float × Float) (h : t.nearestPoint x = some p) :
    p.1.isNaN = false :=
  nearestBy_not_nan _ x p h

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

namespace ValueGroup

/-- The index of the group's x nearest `x`, among those with a position. -/
def nearestIndex (g : ValueGroup) (x : Float) : Option Nat :=
  (nearestBy g.xs.zipIdx x).map (·.2)

theorem nearestIndex_eq (g : ValueGroup) (x : Float) : g.nearestIndex x = (nearestBy g.xs.zipIdx x).map (·.2) := rfl

/-- The index found by `nearestIndex` is that of one of the group's x positions. -/
theorem nearestIndex_lt (g : ValueGroup) (x : Float) (i : Nat) (h : g.nearestIndex x = some i) :
    i < g.xs.size := by
  obtain ⟨p, hp, rfl⟩ := Option.map_eq_some_iff.mp h
  have := Array.mem_zipIdx_iff_getElem?.mp (Array.mem_toList_iff.mp (nearestBy_mem _ x p hp))
  exact (Array.getElem?_eq_some_iff.mp this).1

/-- The group's values at x index `i`, each none where it is missing; none for all where there is no such index. -/
def valuesAt (g : ValueGroup) (i : Option Nat) : Array (Option Float) :=
  g.labels.mapIdx fun j _ =>
    (i.bind fun i => g.values[i]?.bind (·[j]?)).bind fun v => if v.isNaN then none else some v

theorem valuesAt_getElem? (g : ValueGroup) (i : Option Nat) (j : Nat) :
    (g.valuesAt i)[j]? = g.labels[j]?.map fun _ =>
      (i.bind fun i => g.values[i]?.bind (·[j]?)).bind fun v => if v.isNaN then none else some v := by
  simp [valuesAt]

theorem valuesAt_size (g : ValueGroup) (i : Option Nat) : (g.valuesAt i).size = g.labels.size := by
  simp [valuesAt]

/-- The group's texts at x index `i`, each none where it is missing; none for all where there is no such index. -/
def wordsAt (g : ValueGroup) (i : Option Nat) : Array (Option String) :=
  g.labels.mapIdx fun j _ => (i.bind fun i => g.words[i]?.bind (·[j]?)).bind id

theorem wordsAt_getElem? (g : ValueGroup) (i : Option Nat) (j : Nat) :
    (g.wordsAt i)[j]? = g.labels[j]?.map fun _ => (i.bind fun i => g.words[i]?.bind (·[j]?)).bind id := by
  simp [wordsAt]

theorem wordsAt_size (g : ValueGroup) (i : Option Nat) : (g.wordsAt i).size = g.labels.size := by
  simp [wordsAt]

end ValueGroup

namespace Legend

/-- The rows for `traces` with the cursor at data position `x`; with none each shows its series' last value. -/
def rows (traces : Array Trace) (x : Option Float) : Array LegendRow :=
  traces.map fun t =>
    { name := t.name, color := t.color, hidden := t.hidden, value := x.elim t.lastValue t.valueAt, last := x.isNone }

/-- The rows for a group of values, one for each label, at the group's x nearest the cursor at `x`, or at its last x with no cursor. -/
def groupRows (g : ValueGroup) (x : Option Float) : Array LegendRow :=
  let i := x.elim (if g.xs.size = 0 then none else some (g.xs.size - 1)) g.nearestIndex
  let values := g.valuesAt i
  let words := g.wordsAt i
  g.labels.mapIdx fun j label =>
    { name := label, color := g.color, hidden := g.hidden, value := values.getD j none, last := x.isNone,
      word := words.getD j none }

theorem groupRows_size (g : ValueGroup) (x : Option Float) : (groupRows g x).size = g.labels.size := by
  simp [groupRows]

theorem groupRows_getElem? (g : ValueGroup) (x : Option Float) (j : Nat) :
    (groupRows g x)[j]? = g.labels[j]?.map fun label =>
      { name := label, color := g.color, hidden := g.hidden,
        value := (g.valuesAt (x.elim (if g.xs.size = 0 then none else some (g.xs.size - 1)) g.nearestIndex)).getD j none,
        last := x.isNone,
        word := (g.wordsAt (x.elim (if g.xs.size = 0 then none else some (g.xs.size - 1)) g.nearestIndex)).getD j none } := by
  simp [groupRows]

theorem groupRows_last (g : ValueGroup) : ∀ r ∈ groupRows g none, r.last = true := by
  intro r hr
  simp only [groupRows, Array.mem_mapIdx] at hr
  obtain ⟨_, _, rfl⟩ := hr
  rfl

/-- What a row reads as: its name, then its text, else its value, else a dash, marked when it is the last value. -/
def text (r : LegendRow) : String :=
  s!"{r.name}: {r.word.getD ((r.value.map showFloat).getD "-")}{if r.last then " (last)" else ""}"

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
    text r = s!"{r.name}: {r.word.getD ((r.value.map showFloat).getD "-")}{if r.last then " (last)" else ""}" := rfl

/-- Where the legend sits: over the plot at one of its corners, or below the plot, in room of its own, aligned left, centred or right. -/
inductive Placement where
  | topLeft
  | topRight
  | bottomLeft
  | bottomRight
  | belowLeft
  | belowCenter
  | belowRight
  deriving DecidableEq, Repr

/-- Whether the legend lies below the plot rather than over it. -/
def Placement.isBelow : Placement → Bool
  | .belowLeft | .belowCenter | .belowRight => true
  | .topLeft | .topRight | .bottomLeft | .bottomRight => false

theorem Placement.isBelow_eq (p : Placement) :
    p.isBelow = true ↔ (p = .belowLeft ∨ p = .belowCenter ∨ p = .belowRight) := by
  cases p <;> simp [Placement.isBelow]

/-- Whether the entries are listed in a column or in a row, which wraps onto further lines. -/
inductive Layout where
  | vertical
  | horizontal
  deriving DecidableEq, Repr

/-- A legend's placement and layout, whether its entries show values (`live`) or only each series' colour and name, and whether the cursor's x and y positions are shown. -/
structure Style where
  placement : Placement
  layout : Layout
  live : Bool
  showX : Bool
  showY : Bool
  deriving DecidableEq, Repr

private structure Choices where
  placement : Option Placement := none
  layout : Option Layout := none
  live : Bool := true
  showX : Option Bool := none
  showY : Option Bool := none

private def pick {α : Type} [BEq α] (old : Option α) (new : α) : Option (Option α) :=
  match old with
  | none => some (some new)
  | some o => if o == new then some old else none

private def forms : String :=
  "on, off, static, bottom, top-left, top-right, bottom-left, bottom-right, below-left, below-center, below-right, vertical, horizontal, x, y, no-x or no-y, each form at most once and no two of a kind"

private def badLegend (raw : String) : String :=
  s!"attribute legend is \"{raw}\", expected {forms}"

private def choose (c : Choices) : String → Option Choices
  | "on" => some c
  | "static" => some { c with live := false }
  | "top-left" => (pick c.placement .topLeft).map ({ c with placement := · })
  | "top-right" => (pick c.placement .topRight).map ({ c with placement := · })
  | "bottom-left" => (pick c.placement .bottomLeft).map ({ c with placement := · })
  | "bottom-right" => (pick c.placement .bottomRight).map ({ c with placement := · })
  | "below-left" => (pick c.placement .belowLeft).map ({ c with placement := · })
  | "below-center" => (pick c.placement .belowCenter).map ({ c with placement := · })
  | "below-right" | "bottom" => (pick c.placement .belowRight).map ({ c with placement := · })
  | "vertical" => (pick c.layout .vertical).map ({ c with layout := · })
  | "horizontal" => (pick c.layout .horizontal).map ({ c with layout := · })
  | "x" => (pick c.showX true).map ({ c with showX := · })
  | "no-x" => (pick c.showX false).map ({ c with showX := · })
  | "y" => (pick c.showY true).map ({ c with showY := · })
  | "no-y" => (pick c.showY false).map ({ c with showY := · })
  | _ => none

private def finish (c : Choices) : Style :=
  let placement := c.placement.getD .topRight
  { placement
    layout := c.layout.getD (if placement.isBelow then .horizontal else .vertical)
    live := c.live
    showX := c.showX.getD c.live
    showY := c.showY.getD c.live }

/-- The words of `s`, which are separated by spaces. -/
private def words (s : String) : List String :=
  (s.toList.foldr (fun c (acc : List (List Char)) =>
    match c, acc with
    | ' ', [] => []
    | ' ', [] :: _ => acc
    | ' ', _ => [] :: acc
    | c, [] => [[c]]
    | c, w :: ws => (c :: w) :: ws) []).filter (· ≠ []) |>.map String.ofList

/-- Validate the raw `legend` attribute: a missing one or `off` shows none. Otherwise it is a list of words in any order, each kind at most once: `on` (or empty) for the default, which overlays the plot at its top right; a placement, which is `top-left`, `top-right`, `bottom-left` or `bottom-right` over the plot, or `below-left`, `below-center` or `below-right` (`bottom` for the last) in room of its own below it; a layout, `vertical` or `horizontal`, which is a column over the plot and a row below it unless given; `static` to leave out the values; and `x`, `y`, `no-x` or `no-y` to show or hide each cursor position, which are shown when the values are. -/
def parseStyle : Option String → Except String (Option Style)
  | none | some "off" => .ok none
  | some s =>
    match (words s).foldlM choose {} with
    | some c => .ok (some (finish c))
    | none => .error (badLegend s)

theorem parseStyle_none : parseStyle none = .ok none := rfl

theorem parseStyle_off : parseStyle (some "off") = .ok none := rfl

theorem parseStyle_empty :
    parseStyle (some "") = .ok (some { placement := .topRight, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_on :
    parseStyle (some "on") = .ok (some { placement := .topRight, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_bottom :
    parseStyle (some "bottom") = .ok (some { placement := .belowRight, layout := .horizontal, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_static :
    parseStyle (some "static") = .ok (some { placement := .topRight, layout := .vertical, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_static_bottom :
    parseStyle (some "static bottom") = .ok (some { placement := .belowRight, layout := .horizontal, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_on_static :
    parseStyle (some "on static") = .ok (some { placement := .topRight, layout := .vertical, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_static_on :
    parseStyle (some "static on") = .ok (some { placement := .topRight, layout := .vertical, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_bottom_static :
    parseStyle (some "bottom static") = .ok (some { placement := .belowRight, layout := .horizontal, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_top_left : (parseStyle (some "top-left")).toOption = some (some
    { placement := .topLeft, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_top_right : (parseStyle (some "top-right")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_bottom_left : (parseStyle (some "bottom-left")).toOption = some (some
    { placement := .bottomLeft, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_bottom_right : (parseStyle (some "bottom-right")).toOption = some (some
    { placement := .bottomRight, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_below_left : (parseStyle (some "below-left")).toOption = some (some
    { placement := .belowLeft, layout := .horizontal, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_below_center : (parseStyle (some "below-center")).toOption = some (some
    { placement := .belowCenter, layout := .horizontal, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_below_right : (parseStyle (some "below-right")).toOption = some (some
    { placement := .belowRight, layout := .horizontal, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_vertical : (parseStyle (some "vertical")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_horizontal : (parseStyle (some "horizontal")).toOption = some (some
    { placement := .topRight, layout := .horizontal, live := true, showX := true, showY := true }) := by
  rfl

theorem parseStyle_x : (parseStyle (some "static x")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := false, showX := true, showY := false }) := by
  rfl

theorem parseStyle_y : (parseStyle (some "static y")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := false, showX := false, showY := true }) := by
  rfl

theorem parseStyle_no_x : (parseStyle (some "no-x")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := true, showX := false, showY := true }) := by
  rfl

theorem parseStyle_no_y : (parseStyle (some "no-y")).toOption = some (some
    { placement := .topRight, layout := .vertical, live := true, showX := true, showY := false }) := by
  rfl

theorem parseStyle_centred_row : (parseStyle (some "static below-center horizontal")).toOption = some (some
    { placement := .belowCenter, layout := .horizontal, live := false, showX := false, showY := false }) := by
  rfl

theorem parseStyle_column_below : (parseStyle (some "below-left vertical no-x")).toOption = some (some
    { placement := .belowLeft, layout := .vertical, live := true, showX := false, showY := true }) := by
  rfl

theorem parseStyle_unknown (s : String) (h : s = "sideways") :
    parseStyle (some s) = .error (badLegend s) := by
  subst h; rfl

theorem parseStyle_conflict : parseStyle (some "top-left below-left") = .error (badLegend "top-left below-left") := by
  rfl

/-- Whether the raw `legend` attribute shows a legend. -/
def parse (raw : Option String) : Except String Bool :=
  (parseStyle raw).map (·.isSome)

theorem parse_none : parse none = .ok false := rfl

theorem parse_empty : parse (some "") = .ok true := by
  rfl

theorem parse_bottom : parse (some "bottom") = .ok true := by
  rfl

/-- What the cursor readout says: the x position if `showX`, and the y position if `showY` and the pointer is over the chart; none when it says nothing. -/
def readout (showX showY : Bool) (x : Float) (y : Option Float) : Option String :=
  match showX, showY, y with
  | true, true, some y => some s!"x: {showFloat x}, y: {showFloat y}"
  | true, _, _ => some s!"x: {showFloat x}"
  | false, true, some y => some s!"y: {showFloat y}"
  | false, _, _ => none

theorem readout_eq (showX showY : Bool) (x : Float) (y : Option Float) :
    readout showX showY x y = match showX, showY, y with
      | true, true, some y => some s!"x: {showFloat x}, y: {showFloat y}"
      | true, _, _ => some s!"x: {showFloat x}"
      | false, true, some y => some s!"y: {showFloat y}"
      | false, _, _ => none := rfl

theorem readout_none (x : Float) (y : Option Float) : readout false false x y = none := by
  simp [readout]

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
