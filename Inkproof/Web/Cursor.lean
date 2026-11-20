/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Viewport.Gesture

namespace Inkproof.Web

open Inkproof.Viewport

/-- Which lines mark the data position under the pointer. -/
inductive CursorMode where
  | off
  | x
  | y
  | xy
  deriving DecidableEq

namespace CursorMode

/-- Whether the vertical line, at an x position, is drawn. -/
def showsX : CursorMode → Bool
  | .x | .xy => true
  | _ => false

/-- Whether the horizontal line, at a y position, is drawn. -/
def showsY : CursorMode → Bool
  | .y | .xy => true
  | _ => false

/-- Validate the raw `cursor` value. A missing one draws no cursor. -/
def parse : Option String → Except String CursorMode
  | none | some "off" => .ok .off
  | some "x" => .ok .x
  | some "y" => .ok .y
  | some "xy" => .ok .xy
  | some s => .error s!"attribute cursor is \"{s}\", expected off, x, y or xy"

theorem showsX_iff (m : CursorMode) : m.showsX = true ↔ m = .x ∨ m = .xy := by
  cases m <;> simp [showsX]

theorem showsY_iff (m : CursorMode) : m.showsY = true ↔ m = .y ∨ m = .xy := by
  cases m <;> simp [showsY]

theorem parse_none : parse none = .ok .off := rfl

theorem parse_xy : parse (some "xy") = .ok .xy := rfl

theorem parse_invalid (s : String) (h : s ≠ "off" ∧ s ≠ "x" ∧ s ≠ "y" ∧ s ≠ "xy") : ∃ e, parse (some s) = .error e := by
  obtain ⟨h₁, h₂, h₃, h₄⟩ := h
  unfold parse
  split <;> first | exact ⟨_, rfl⟩ | simp_all

end CursorMode

/-- A line from `(x₁, y₁)` to `(x₂, y₂)`, in pixels from the plot's top left. -/
structure Line where
  x₁ : Float
  y₁ : Float
  x₂ : Float
  y₂ : Float

namespace Cursor

/-- The lines for a cursor at data position `x`, and `y` if the pointer is over this chart, under `view`. Each spans the plot; one whose position is off the plot or not a number is dropped. -/
def lines (mode : CursorMode) (config : ViewConfig Float) (view : View Float) (x : Float) (y : Option Float) : Array Line :=
  let px := view.x.toScreen config.x x
  let vertical :=
    if mode.showsX && 0 ≤ px && px ≤ config.x.length then #[⟨px, 0, px, config.y.length⟩] else #[]
  let horizontal := match y with
    | some y =>
      let py := config.y.length - view.y.toScreen config.y y
      if mode.showsY && 0 ≤ py && py ≤ config.y.length then #[⟨0, py, config.x.length, py⟩] else #[]
    | none => #[]
  vertical ++ horizontal

theorem lines_off (config : ViewConfig Float) (view : View Float) (x : Float) (y : Option Float) :
    lines .off config view x y = #[] := by
  cases y <;> simp [lines, CursorMode.showsX, CursorMode.showsY]

theorem lines_x_only (config : ViewConfig Float) (view : View Float) (x y : Float) :
    lines .x config view x (some y) = lines .x config view x none := by
  simp [lines, CursorMode.showsY]

theorem lines_vertical (mode : CursorMode) (config : ViewConfig Float) (view : View Float) (x : Float)
    (hm : mode.showsX = true) (h₀ : 0 ≤ view.x.toScreen config.x x) (h₁ : view.x.toScreen config.x x ≤ config.x.length) :
    lines mode config view x none =
      #[⟨view.x.toScreen config.x x, 0, view.x.toScreen config.x x, config.y.length⟩] := by
  simp [lines, hm, h₀, h₁]

theorem lines_horizontal (mode : CursorMode) (config : ViewConfig Float) (view : View Float) (x y : Float)
    (hm : mode.showsY = true) (hx : ¬(mode.showsX = true))
    (h₀ : 0 ≤ config.y.length - view.y.toScreen config.y y)
    (h₁ : config.y.length - view.y.toScreen config.y y ≤ config.y.length) :
    lines mode config view x (some y) =
      #[⟨0, config.y.length - view.y.toScreen config.y y, config.x.length, config.y.length - view.y.toScreen config.y y⟩] := by
  simp [lines, hm, hx, h₀, h₁]

end Cursor

end Inkproof.Web
