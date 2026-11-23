/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Legend

namespace Inkproof.Web

open Inkproof.Viewport

/-- Which series carry a marker at the cursor. -/
inductive MarkerMode where
  | off
  | all
  | nearest
  deriving DecidableEq

namespace MarkerMode

end MarkerMode

/-- How a cursor marker looks: its diameter in pixels, and whether it is filled or an outline. -/
structure MarkerStyle where
  size : Float := 6
  filled : Bool := true

namespace MarkerStyle

end MarkerStyle

/-- A marker at `(x, y)` in pixels from the plot's top left, for series `series`. -/
structure Marker where
  series : Nat
  x : Float
  y : Float
  color : String
  filled : Bool

namespace Marker

/-- Where the trace's point nearest data position `x` lies under `view`, in pixels from the plot's top left; none when that point has no value or lies off the plot. -/
def position (config : ViewConfig Float) (view : View Float) (t : Trace) (x : Float) : Option (Float × Float) :=
  (t.nearestPoint x).bind fun (px, py) =>
    if py.isNaN then none else
      let sx := view.x.toScreen config.x px
      let sy := config.y.length - view.y.toScreen config.y py
      if 0 ≤ sx && sx ≤ config.x.length && 0 ≤ sy && sy ≤ config.y.length then some (sx, sy) else none

theorem position_eq (config : ViewConfig Float) (view : View Float) (t : Trace) (x px py : Float)
    (hn : t.nearestPoint x = some (px, py)) :
    position config view t x =
      if py.isNaN then none else
        if 0 ≤ view.x.toScreen config.x px && view.x.toScreen config.x px ≤ config.x.length &&
            0 ≤ config.y.length - view.y.toScreen config.y py &&
            config.y.length - view.y.toScreen config.y py ≤ config.y.length then
          some (view.x.toScreen config.x px, config.y.length - view.y.toScreen config.y py)
        else none := by
  simp [position, hn]

theorem position_none (config : ViewConfig Float) (view : View Float) (t : Trace) (x : Float)
    (hn : t.nearestPoint x = none) : position config view t x = none := by
  simp [position, hn]

/-- The marker of series `series` at data position `x`: none for a hidden series or one with no value there. A series drawn with hollow markers gets a filled one, whatever the style. -/
def ofTrace (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (x : Float) (series : Nat) (t : Trace) : Option Marker :=
  if t.hidden then none else
    (position config view t x).map fun (sx, sy) =>
      { series, x := sx, y := sy, color := t.color, filled := style.filled || t.hollow }

theorem ofTrace_hidden (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (x : Float) (series : Nat) (t : Trace)
    (h : t.hidden = true) : ofTrace style config view x series t = none := by
  simp [ofTrace, h]

theorem ofTrace_eq (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (x : Float) (series : Nat) (t : Trace)
    (h : t.hidden = false) (p : Float × Float) (hp : position config view t x = some p) :
    ofTrace style config view x series t =
      some { series, x := p.1, y := p.2, color := t.color, filled := style.filled || t.hollow } := by
  simp [ofTrace, h, hp]

theorem ofTrace_none (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (x : Float) (series : Nat) (t : Trace)
    (hp : position config view t x = none) : ofTrace style config view x series t = none := by
  simp [ofTrace, hp]

end Marker

namespace Markers

/-- The marker nearest the pointer: by `y` in pixels when the pointer's is known, otherwise by `x`; the first of equals. No theorem says it is a minimiser: `Float` has no `LinearOrder` (NaN is unordered), so `List.minOn?` lemmas don't apply and a proof would need a NaN-free hypothesis on every marker. -/
def nearestOf (px : Float) (py : Option Float) (ms : List Marker) : Option Marker :=
  ms.minOn? fun m => match py with
    | some py => (m.y - py).abs
    | none => (m.x - px).abs

/-- The markers for a cursor at data position `x`, and `y` if the pointer is over this chart, under `view`: one per visible series with a value at `x` for `all`, the one nearest the pointer for `nearest`. -/
def atCursor (mode : MarkerMode) (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (traces : Array Trace)
    (x : Float) (y : Option Float) : Array Marker :=
  let all := traces.toList.zipIdx.filterMap fun (t, s) => Marker.ofTrace style config view x s t
  match mode with
  | .off => #[]
  | .all => all.toArray
  | .nearest =>
    let py := y.map fun y => config.y.length - view.y.toScreen config.y y
    (nearestOf (view.x.toScreen config.x x) py all).toList.toArray

theorem atCursor_off (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (traces : Array Trace) (x : Float) (y : Option Float) :
    atCursor .off style config view traces x y = #[] := rfl

theorem atCursor_all (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (traces : Array Trace) (x : Float) (y : Option Float) :
    atCursor .all style config view traces x y =
      (traces.toList.zipIdx.filterMap fun (t, s) => Marker.ofTrace style config view x s t).toArray := rfl

theorem atCursor_nearest (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (traces : Array Trace) (x : Float) (y : Option Float) :
    atCursor .nearest style config view traces x y =
      (nearestOf (view.x.toScreen config.x x) (y.map fun y => config.y.length - view.y.toScreen config.y y)
        (traces.toList.zipIdx.filterMap fun (t, s) => Marker.ofTrace style config view x s t)).toList.toArray := rfl

/-- A marker of `all` is that of a series of the chart, at the projected position of its value at `x`. -/
theorem mem_atCursor_all (style : MarkerStyle) (config : ViewConfig Float) (view : View Float) (traces : Array Trace) (x : Float) (y : Option Float)
    (m : Marker) : m ∈ atCursor .all style config view traces x y ↔
      ∃ t, traces[m.series]? = some t ∧ Marker.ofTrace style config view x m.series t = some m := by
  simp only [atCursor_all, List.mem_toArray, List.mem_filterMap, List.mem_zipIdx_iff_getElem?]
  constructor
  · rintro ⟨⟨t, s⟩, h1, h2⟩
    have hs : s = m.series := by
      unfold Marker.ofTrace at h2
      split at h2
      · simp at h2
      · simp only [Option.map_eq_some_iff] at h2
        obtain ⟨_, _, rfl⟩ := h2
        rfl
    subst hs
    exact ⟨t, by simpa [Array.getElem?_toList] using h1, h2⟩
  · rintro ⟨t, h1, h2⟩
    exact ⟨(t, m.series), by simpa [Array.getElem?_toList] using h1, h2⟩

end Markers

end Inkproof.Web
