/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

/-- Device pixel ratio as thousandths, so sizing is exact integer arithmetic. -/
abbrev Milli := Nat

/-- Backing-store pixels for a CSS length: `css * ratio` rounded to the nearest pixel, and at least one so a visible element never gets a zero-sized canvas. -/
def backingPx (css : Nat) (ratio : Milli) : Nat :=
  if css = 0 then 0 else max 1 ((css * ratio + 500) / 1000)

theorem backingPx_zero (ratio : Milli) : backingPx 0 ratio = 0 := by
  simp [backingPx]

theorem backingPx_pos {css : Nat} (h : 0 < css) (ratio : Milli) : 0 < backingPx css ratio := by
  have : css ≠ 0 := Nat.pos_iff_ne_zero.mp h
  simp [backingPx, this]
  omega

/-- The rounding error is at most half a pixel whenever the result is not clamped up to one. -/
theorem backingPx_close {css : Nat} (ratio : Milli) (h : 1000 ≤ css * ratio + 500) (hc : css ≠ 0) :
    backingPx css ratio * 1000 ≤ css * ratio + 500 ∧ css * ratio < backingPx css ratio * 1000 + 500 := by
  have h1 : 1 ≤ (css * ratio + 500) / 1000 := by omega
  simp only [backingPx, hc, ite_false]
  rw [Nat.max_eq_right h1]
  omega

/-- A canvas size in backing-store pixels. -/
structure Size where
  width : Nat
  height : Nat
  deriving DecidableEq, Repr

/-- The backing store for an element of the given CSS size at the given device pixel ratio. -/
def Size.backing (cssWidth cssHeight : Nat) (ratio : Milli) : Size :=
  ⟨backingPx cssWidth ratio, backingPx cssHeight ratio⟩

theorem Size.backing_width (w h : Nat) (ratio : Milli) : (Size.backing w h ratio).width = backingPx w ratio := rfl

theorem Size.backing_height (w h : Nat) (ratio : Milli) : (Size.backing w h ratio).height = backingPx h ratio := rfl

/-- Whether the canvas must be resized (and so redrawn, since resizing clears it). -/
def Size.needsResize (current : Size) (cssWidth cssHeight : Nat) (ratio : Milli) : Bool :=
  current != Size.backing cssWidth cssHeight ratio

theorem Size.needsResize_iff (current : Size) (w h : Nat) (ratio : Milli) :
    current.needsResize w h ratio = true ↔ current ≠ Size.backing w h ratio := by
  simp [needsResize]

end Inkproof.Web
