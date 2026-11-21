/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Float.OrdFloat
import Inkproof.Viewport.View

namespace Inkproof.Web

open Inkproof.Float Inkproof.Viewport

/-- One series as the tooltip and legend read it: its points, in data coordinates. -/
structure Trace where
  name : String
  color : String
  xs : Array Float
  ys : Array Float
  hidden : Bool := false

namespace Trace

/-- The trace with its points in pixels from the plot's top left under `view`, y upwards on the screen. -/
def onScreen (config : ViewConfig Float) (view : View Float) (t : Trace) : Trace :=
  { t with
    xs := t.xs.map (view.x.toScreen config.x)
    ys := t.ys.map fun y => config.y.length - view.y.toScreen config.y y }

theorem onScreen_size (config : ViewConfig Float) (view : View Float) (t : Trace) :
    (t.onScreen config view).xs.size = t.xs.size ∧ (t.onScreen config view).ys.size = t.ys.size := by
  simp [onScreen]

theorem onScreen_xs (config : ViewConfig Float) (view : View Float) (t : Trace) :
    (t.onScreen config view).xs = t.xs.map (view.x.toScreen config.x) := rfl

theorem onScreen_ys (config : ViewConfig Float) (view : View Float) (t : Trace) :
    (t.onScreen config view).ys = t.ys.map fun y => config.y.length - view.y.toScreen config.y y := rfl

end Trace

/-- A point of a trace: its series, its index and its position. -/
structure Candidate where
  series : Nat
  point : Nat
  x : Float
  y : Float

/-- What nearness to the pointer is measured in. -/
inductive Metric where
  | x
  | plane
  deriving DecidableEq

namespace Metric

/-- The distance from `(cx, cy)` to `c`: along x only, or squared in the plane. -/
def dist : Metric → Float → Float → Candidate → Float
  | .x, cx, _, c => (c.x - cx).abs
  | .plane, cx, cy, c => (c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy)

/-- Validate the raw `tooltip` value. A missing one shows no tooltip. -/
def parse : Option String → Except String (Option Metric)
  | none | some "off" => .ok none
  | some "x" => .ok (some .x)
  | some "xy" => .ok (some .plane)
  | some s => .error s!"attribute tooltip is \"{s}\", expected off, x or xy"

theorem dist_x (cx cy : Float) (c : Candidate) : dist .x cx cy c = (c.x - cx).abs := rfl

theorem dist_plane (cx cy : Float) (c : Candidate) :
    dist .plane cx cy c = (c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy) := rfl

theorem parse_none : parse none = .ok none := rfl

theorem parse_xy : parse (some "xy") = .ok (some .plane) := rfl

end Metric

namespace Nearest

private def pick (d : Candidate → Float) (b c : Candidate) : Candidate := if d b ≤ d c then b else c

/-- The first candidate of least distance. -/
def argmin (d : Candidate → Float) : List Candidate → Option Candidate
  | [] => none
  | a :: t => some (t.foldl (pick d) a)

private theorem foldl_pick (d : Candidate → Float) (ordered : ∀ c, Float.IsOrdered (d c)) (t : List Candidate) :
    ∀ a : Candidate, (t.foldl (pick d) a ∈ a :: t) ∧ ∀ k ∈ a :: t, d (t.foldl (pick d) a) ≤ d k := by
  induction t with
  | nil => intro a; simpa using float_le_linear.1 _ (ordered a)
  | cons j t ih =>
    intro a
    obtain ⟨hmem, hle⟩ := ih (pick d a j)
    have hpick : d (pick d a j) ≤ d a ∧ d (pick d a j) ≤ d j := by
      unfold pick
      split
      · rename_i h
        exact ⟨float_le_linear.1 _ (ordered a), h⟩
      · rename_i h
        refine ⟨?_, float_le_linear.1 _ (ordered j)⟩
        rcases float_le_linear.2.2.2 _ _ (ordered a) (ordered j) with h' | h'
        · exact absurd h' h
        · exact h'
    have hpm : pick d a j = a ∨ pick d a j = j := by unfold pick; split <;> simp
    refine ⟨?_, ?_⟩
    · have := hmem
      simp only [List.mem_cons] at this ⊢
      rcases this with h | h
      · rcases hpm with hp | hp
        · exact Or.inl (h.trans hp)
        · exact Or.inr (Or.inl (h.trans hp))
      · exact Or.inr (Or.inr h)
    · intro k hk
      simp only [List.mem_cons] at hk
      rcases hk with rfl | rfl | hk
      · exact float_le_linear.2.1 _ _ _ (ordered _) (ordered _) (ordered _)
          (hle _ (by simp [List.mem_cons])) hpick.1
      · exact float_le_linear.2.1 _ _ _ (ordered _) (ordered _) (ordered _)
          (hle _ (by simp [List.mem_cons])) hpick.2
      · exact hle k (by simp [hk])

theorem argmin_mem (d : Candidate → Float) (ordered : ∀ c, Float.IsOrdered (d c)) (cs : List Candidate) (r : Candidate)
    (h : argmin d cs = some r) : r ∈ cs := by
  cases cs with
  | nil => simp [argmin] at h
  | cons a t =>
    simp only [argmin, Option.some.injEq] at h
    exact h ▸ (foldl_pick d ordered t a).1

/-- No candidate is nearer than the one chosen. -/
theorem argmin_least (d : Candidate → Float) (ordered : ∀ c, Float.IsOrdered (d c)) (cs : List Candidate) (r : Candidate)
    (h : argmin d cs = some r) : ∀ c ∈ cs, d r ≤ d c := by
  cases cs with
  | nil => simp [argmin] at h
  | cons a t =>
    simp only [argmin, Option.some.injEq] at h
    exact h ▸ (foldl_pick d ordered t a).2

theorem argmin_eq_none (d : Candidate → Float) (cs : List Candidate) : argmin d cs = none ↔ cs = [] := by
  cases cs <;> simp [argmin]

/-- The points of the visible traces that have a position, in order. -/
def candidates (traces : Array Trace) : List Candidate :=
  (traces.toList.zipIdx.flatMap fun (t, s) =>
    if t.hidden then [] else
      (t.xs.zip t.ys).toList.zipIdx.filterMap fun ((x, y), i) =>
        if x.isNaN || y.isNaN then none else some ⟨s, i, x, y⟩)

/-- The visible point nearest to `(cx, cy)` under `metric`, and the first of equals. -/
def find (metric : Metric) (traces : Array Trace) (cx cy : Float) : Option Candidate :=
  argmin (metric.dist cx cy) (candidates traces)

/-- A candidate is a point of a visible series that has a position, with that series and index. -/
theorem mem_candidates (traces : Array Trace) (c : Candidate) :
    c ∈ candidates traces ↔ ∃ t, traces[c.series]? = some t ∧ t.hidden = false ∧
      t.xs[c.point]? = some c.x ∧ t.ys[c.point]? = some c.y ∧ c.x.isNaN = false ∧ c.y.isNaN = false := by
  simp only [candidates, Array.toList_zip, List.mem_flatMap, List.mem_zipIdx_iff_getElem?]
  constructor
  · rintro ⟨⟨t, s⟩, h1, h2⟩
    by_cases hh : t.hidden = true
    · simp [hh] at h2
    · have hh' : t.hidden = false := by simpa using hh
      simp only [hh', Bool.false_eq_true, ite_false, List.mem_filterMap] at h2
      obtain ⟨⟨⟨x, y⟩, i⟩, h3, h4⟩ := h2
      split at h4
      · simp at h4
      · simp only [Option.some.injEq] at h4
        subst h4
        rw [List.mem_zipIdx_iff_getElem?, List.getElem?_zip_eq_some] at h3
        simp only [Bool.or_eq_true, not_or, Bool.not_eq_true] at *
        exact ⟨t, by simpa [Array.getElem?_toList] using h1, hh', by simpa using h3.1, by simpa using h3.2, ‹_ ∧ _›.1, ‹_ ∧ _›.2⟩
  · rintro ⟨t, h1, hh, hx, hy, nx, ny⟩
    refine ⟨(t, c.series), by simpa using h1, ?_⟩
    simp only [hh, Bool.false_eq_true, ite_false, List.mem_filterMap]
    refine ⟨((c.x, c.y), c.point), ?_, ?_⟩
    · rw [List.mem_zipIdx_iff_getElem?, List.getElem?_zip_eq_some]
      simpa using ⟨hx, hy⟩
    · simp [nx, ny]

theorem find_none_iff (metric : Metric) (traces : Array Trace) (cx cy : Float) :
    find metric traces cx cy = none ↔ candidates traces = [] := argmin_eq_none _ _

/-- The point found is one of the visible traces' points, and none of them is nearer, provided the pointer and the points are numbers. -/
theorem find_least (metric : Metric) (traces : Array Trace) (cx cy : Float)
    (ordered : ∀ c, Float.IsOrdered (metric.dist cx cy c)) (r : Candidate) (h : find metric traces cx cy = some r) :
    r ∈ candidates traces ∧ ∀ c ∈ candidates traces, metric.dist cx cy r ≤ metric.dist cx cy c :=
  ⟨argmin_mem _ ordered _ r h, argmin_least _ ordered _ r h⟩

end Nearest

end Inkproof.Web
