/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Viewport.Gesture

namespace Inkproof.Web

open Inkproof.Viewport

/-- How a shift-drag box zooms: the axes it covers and the least drag, in pixels, that counts as a selection. -/
structure BoxConfig where
  axes : Gesture.Axes := .both
  minDistance : Float := Gesture.minBox

namespace BoxConfig

/-- The box zoom for a drag between two positions on the plot. -/
def input (c : BoxConfig) (v : ViewConfig Float) (a b : Px) : Option (Input Float) :=
  Gesture.boxOver v c.axes c.minDistance a b

theorem input_default (v : ViewConfig Float) (a b : Px) :
    ({} : BoxConfig).input v a b = Gesture.box v a b :=
  (Gesture.box_eq_boxOver v a b).symm

/-- Validate the raw `box-zoom` and `box-min` values. A missing one is the default; an unrecognised or non-positive one is an error. -/
def parse (axes minDistance : Option String) : Except String BoxConfig := do
  let axes ← match axes with
    | none | some "xy" => pure Gesture.Axes.both
    | some "x" => pure .x
    | some "y" => pure .y
    | some "auto" => pure .auto
    | some s => throw s!"attribute box-zoom is \"{s}\", expected x, y, xy or auto"
  let minDistance ← match minDistance with
    | none => pure Gesture.minBox
    | some s => match s.toNat? with
      | some n => if n == 0 then throw "attribute box-min is 0, expected a positive number of pixels" else pure n.toFloat
      | none => throw s!"attribute box-min is \"{s}\", expected a whole number of pixels"
  return { axes, minDistance }

theorem parse_default : ∃ c, parse none none = .ok c ∧ c.axes = .both ∧ c.minDistance = Gesture.minBox :=
  ⟨_, rfl, rfl, rfl⟩

theorem parse_axes (s : String) (a : Gesture.Axes) (h : s = "x" ∧ a = .x ∨ s = "y" ∧ a = .y ∨ s = "xy" ∧ a = .both ∨ s = "auto" ∧ a = .auto) :
    ∃ c, parse (some s) none = .ok c ∧ c.axes = a := by
  rcases h with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ <;> exact ⟨_, rfl, rfl⟩

theorem parse_minDistance (s : String) (n : Nat) (h : s.toNat? = some n) (hn : n ≠ 0) :
    ∃ c, parse none (some s) = .ok c ∧ c.minDistance = n.toFloat := by
  simp [parse, h, hn]
  exact ⟨_, rfl, rfl⟩

theorem parse_minDistance_zero (s : String) (h : s.toNat? = some 0) : ∃ e, parse none (some s) = .error e := by
  simp [parse, h]
  exact ⟨_, rfl⟩

theorem parse_minDistance_invalid (s : String) (h : s.toNat? = none) : ∃ e, parse none (some s) = .error e := by
  simp [parse, h]
  exact ⟨_, rfl⟩

end BoxConfig

end Inkproof.Web
