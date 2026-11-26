/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Legend

namespace Inkproof.Web

namespace Tooltip

/-- What the tooltip is placed against: the nearest data point, or the pointer. -/
inductive Anchor where
  | point
  | pointer
  deriving DecidableEq, Repr

/-- How a tooltip reads, how it is found and where it opens. It opens to the right (`right`) or the left of the anchor, and from above (`top`) or below, `offset` pixels from it. `shared` lists every series at the cursor's x, so it is found by x. -/
structure Style where
  metric : Metric
  shared : Bool
  showX : Bool
  anchor : Anchor
  right : Bool
  top : Bool
  offset : Nat

private structure Choices where
  metric : Option Metric := none
  shared : Bool := false
  showX : Bool := true
  anchor : Option Anchor := none
  right : Option Bool := none
  top : Option Bool := none
  offset : Option Nat := none

private def forms : String :=
  "off, x, xy, shared, no-x-value, point, pointer, top-right, top-left, bottom-right, bottom-left or a number of pixels, each kind at most once, and not shared with xy"

private def choose (c : Choices) (w : String) : Option Choices :=
  let corner (top right : Bool) : Option Choices := do
    let t ← Legend.pick c.top top
    let r ← Legend.pick c.right right
    some { c with top := t, right := r }
  match w with
  | "x" => (Legend.pick c.metric .x).map ({ c with metric := · })
  | "xy" => (Legend.pick c.metric .plane).map ({ c with metric := · })
  | "shared" => some { c with shared := true }
  | "no-x-value" => some { c with showX := false }
  | "point" => (Legend.pick c.anchor .point).map ({ c with anchor := · })
  | "pointer" => (Legend.pick c.anchor .pointer).map ({ c with anchor := · })
  | "top-right" => corner true true
  | "top-left" => corner true false
  | "bottom-right" => corner false true
  | "bottom-left" => corner false false
  | _ => w.toNat?.bind fun n => (Legend.pick c.offset n).map ({ c with offset := · })

private def finish (c : Choices) : Option Style :=
  let metric := c.metric.getD .x
  if c.shared && metric == .plane then none
  else some { metric, shared := c.shared, showX := c.showX, anchor := c.anchor.getD .point,
              right := c.right.getD true, top := c.top.getD true, offset := c.offset.getD 8 }

/-- Validate the raw `tooltip` attribute: a missing one or `off` shows none. Otherwise it is a list of words in any order: `x` (the default) or `xy`, the metric by which the nearest point is found; `shared` to list every series at the cursor's x rather than the nearest point; `no-x-value` to leave out the x value; `point` (the default) or `pointer`, what it is placed against; `top-right` (the default), `top-left`, `bottom-right` or `bottom-left`, the way it opens; and a number of pixels, 8 by default, between the anchor and its nearest corner. -/
def parse : Option String → Except String (Option Style)
  | none | some "off" => .ok none
  | some s =>
    match ((Legend.words s).foldlM choose {}).bind finish with
    | some style => .ok (some style)
    | none => .error s!"attribute tooltip is \"{s}\", expected {forms}"

theorem parse_none : parse none = .ok none := rfl

theorem parse_some (s : String) :
    parse (some s) =
      if s = "off" then .ok none
      else match ((Legend.words s).foldlM choose {}).bind finish with
        | some style => .ok (some style)
        | none => .error s!"attribute tooltip is \"{s}\", expected {forms}" := by
  by_cases h : s = "off" <;> simp [parse, h]

theorem parse_off : parse (some "off") = .ok none := rfl

/-- The tooltip's start along one axis: `first` where it fits in `[0, bound]`, else `second` where that fits, else `first` moved inside, to the start if `size` exceeds `bound`. -/
def fit (first second size bound : Float) : Float :=
  let fits (s : Float) := 0 ≤ s && s + size ≤ bound
  if fits first then first else if fits second then second
  else max 0 (min first (bound - size))

theorem fit_eq (first second size bound : Float) :
    fit first second size bound =
      (if (0 ≤ first && first + size ≤ bound) = true then first
        else if (0 ≤ second && second + size ≤ bound) = true then second
        else max 0 (min first (bound - size))) := rfl

/-- The tooltip's start along an axis for an anchor at `anchor`: on the `forward` side its near edge lies `offset` ahead of the anchor, otherwise `offset` behind it; the other side is where it goes when that does not fit. -/
def Style.start (offset anchor size bound : Float) (forward : Bool) : Float :=
  let ahead := anchor + offset
  let behind := anchor - offset - size
  if forward then fit ahead behind size bound else fit behind ahead size bound

theorem Style.start_eq (offset anchor size bound : Float) (forward : Bool) :
    Style.start offset anchor size bound forward =
      if forward then fit (anchor + offset) (anchor - offset - size) size bound
      else fit (anchor - offset - size) (anchor + offset) size bound := rfl

/-- The top left of a tooltip of `w` by `h` for an anchor at `(x, y)` in a chart of `width` by `height`, all in pixels from the chart's top left. Opening `top-right` puts its top left corner at `(x + offset, y - offset)`, and the other corners mirror that. -/
def Style.place (s : Style) (x y w h width height : Float) : Float × Float :=
  let d := s.offset.toFloat
  (Style.start d x w width s.right,
   if s.top then fit (y - d) (y + d - h) h height else fit (y + d - h) (y - d) h height)

theorem Style.place_eq (s : Style) (x y w h width height : Float) :
    s.place x y w h width height =
      (Style.start s.offset.toFloat x w width s.right,
       if s.top then fit (y - s.offset.toFloat) (y + s.offset.toFloat - h) h height
       else fit (y + s.offset.toFloat - h) (y - s.offset.toFloat) h height) := rfl

/-- What a tooltip at `c` reads: the series, with the point's label if it has one, then the point's x unless left out, its y and its size if it has one. -/
def single (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (c : Candidate) : Option String := do
  let t ← traces[c.series]?
  let x ← t.xs[c.point]?
  let y ← t.ys[c.point]?
  let name := match t.labels[c.point]? with
    | some l => s!"{t.name}, {l}"
    | none => t.name
  let values := (if showX then [showNumber fmt x] else []) ++ [showNumber fmt y] ++
    ((t.sizes[c.point]?).map (showNumber fmt)).toList
  some (name ++ ": " ++ ", ".intercalate values)

theorem single_eq (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (c : Candidate) (t : Trace) (x y : Float)
    (ht : traces[c.series]? = some t) (hx : t.xs[c.point]? = some x) (hy : t.ys[c.point]? = some y) :
    single fmt showX traces c =
      some ((match t.labels[c.point]? with | some l => s!"{t.name}, {l}" | none => t.name) ++ ": " ++
        ", ".intercalate ((if showX then [showNumber fmt x] else []) ++ [showNumber fmt y] ++
          ((t.sizes[c.point]?).map (showNumber fmt)).toList)) := by
  simp [single, ht, hx, hy]

/-- Without labels or sizes the tooltip reads as it always did: the series, then the x unless left out, and the y. -/
theorem single_plain (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (c : Candidate) (t : Trace) (x y : Float)
    (ht : traces[c.series]? = some t) (hx : t.xs[c.point]? = some x) (hy : t.ys[c.point]? = some y)
    (hl : t.labels[c.point]? = none) (hs : t.sizes[c.point]? = none) :
    single fmt showX traces c =
      some (if showX then s!"{t.name}: {showNumber fmt x}, {showNumber fmt y}" else s!"{t.name}: {showNumber fmt y}") := by
  cases showX <;> simp [single, ht, hx, hy, hl, hs, String.append_assoc] <;> rfl

/-- What a shared tooltip at the cursor's x reads: the x unless left out, then a line for each visible series with its value there. None when no series is visible. -/
def sharedText (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (x : Float) : Option String :=
  let rows := (Legend.rows traces (some x)).filter (!·.hidden)
  if rows.isEmpty then none
  else some ("\n".intercalate ((if showX then [s!"x: {showNumber fmt x}"] else []) ++ (rows.map (Legend.text fmt)).toList))

theorem sharedText_eq (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (x : Float)
    (h : ((Legend.rows traces (some x)).filter (!·.hidden)).isEmpty = false) :
    sharedText fmt showX traces x =
      some ("\n".intercalate ((if showX then [s!"x: {showNumber fmt x}"] else []) ++
        (((Legend.rows traces (some x)).filter (!·.hidden)).map (Legend.text fmt)).toList)) := by
  simp [sharedText, h]

theorem sharedText_none_of_hidden (fmt : Option Inkproof.Axis.NumberFormat) (showX : Bool) (traces : Array Trace) (x : Float)
    (h : ∀ t ∈ traces, t.hidden = true) : sharedText fmt showX traces x = none := by
  have : ((Legend.rows traces (some x)).filter (!·.hidden)).isEmpty = true := by
    simp only [Array.isEmpty_iff_size_eq_zero, Array.size_eq_zero_iff, Array.filter_eq_empty_iff, Legend.rows,
      Array.mem_map]
    rintro r ⟨t, ht, rfl⟩
    simp [h t ht]
  simp [sharedText, this]

end Tooltip

end Inkproof.Web
