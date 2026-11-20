/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Viewport.Selection
import Inkproof.Viewport.View

namespace Inkproof.Web

open Inkproof.Viewport

/-- Whether a drag on the chart edits a selected x range instead of changing the chart's view. -/
inductive SelectMode where
  | off
  | x
  deriving DecidableEq

namespace SelectMode

/-- Validate the raw `select` value. A missing one selects nothing. -/
def parse : Option String → Except String SelectMode
  | none | some "off" => .ok .off
  | some "x" => .ok .x
  | some s => .error s!"attribute select is \"{s}\", expected off or x"

theorem parse_none : parse none = .ok .off := rfl

theorem parse_x : parse (some "x") = .ok .x := rfl

theorem parse_invalid (s : String) (h : s ≠ "off" ∧ s ≠ "x") : ∃ e, parse (some s) = .error e := by
  obtain ⟨h₁, h₂⟩ := h
  unfold parse
  split <;> first | exact ⟨_, rfl⟩ | simp_all

end SelectMode

namespace Select

/-- The least width of a band, in pixels. -/
def minPixels : Float := 3

/-- How far from an edge a press grabs it, in pixels. -/
def grabPixels : Float := 6

/-- The selection settings for a plot: bands lie within the view the chart starts in, and the pixel distances become data distances at that view's scale. -/
def config (c : ViewConfig Float) : Selection.Config Float :=
  let domain := (View.home c).x
  let unit := domain.span / c.x.length
  { domain, minWidth := minPixels * unit, tolerance := grabPixels * unit }

theorem config_domain (c : ViewConfig Float) : (config c).domain = (View.home c).x := rfl

theorem config_minWidth (c : ViewConfig Float) :
    (config c).minWidth = minPixels * ((View.home c).x.span / c.x.length) := rfl

theorem config_tolerance (c : ViewConfig Float) :
    (config c).tolerance = grabPixels * ((View.home c).x.span / c.x.length) := rfl

/-- The view `view` shows when it follows `band`: the band's x range, its own y range. -/
def shown (view : View Float) (band : Selection.Band Float) : View Float := { view with x := band.toInterval }

theorem shown_x (view : View Float) (band : Selection.Band Float) : (shown view band).x = band.toInterval := rfl

theorem shown_y (view : View Float) (band : Selection.Band Float) : (shown view band).y = view.y := rfl

/-- The band that `view`'s x range covers, if it is wide enough to be one. -/
def following (c : ViewConfig Float) (view : View Float) : Option (Selection.Band Float) :=
  Selection.ofInterval (config c) view.x

theorem following_eq (c : ViewConfig Float) (view : View Float) :
    following c view = Selection.draw (config c) view.x.start (view.x.start + view.x.span) := rfl

/-- The horizontal pixel extent of `band` on a plot showing `view`. -/
def extent (c : ViewConfig Float) (view : View Float) (band : Selection.Band Float) : Float × Float :=
  (view.x.toScreen c.x band.lo, view.x.toScreen c.x band.hi)

theorem extent_eq (c : ViewConfig Float) (view : View Float) (band : Selection.Band Float) :
    extent c view band = (view.x.toScreen c.x band.lo, view.x.toScreen c.x band.hi) := rfl

end Select

end Inkproof.Web
