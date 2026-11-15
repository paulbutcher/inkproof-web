/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

/-- Whether anything has changed since the last frame was drawn. -/
structure Frame where
  dirty : Bool
  deriving DecidableEq, Repr

namespace Frame

/-- A new chart has never been drawn. -/
def initial : Frame := ⟨true⟩

/-- Record a change in the command list, the size, the ratio, or a restored context. -/
def invalidate (_ : Frame) : Frame := ⟨true⟩

/-- Whether the next animation frame must draw. -/
def shouldDraw (f : Frame) : Bool := f.dirty

/-- The state after an animation frame. -/
def drawn (_ : Frame) : Frame := ⟨false⟩

theorem shouldDraw_initial : initial.shouldDraw = true := rfl

theorem shouldDraw_invalidate (f : Frame) : f.invalidate.shouldDraw = true := rfl

/-- Nothing is redrawn when nothing changed. -/
theorem not_shouldDraw_drawn (f : Frame) : f.drawn.shouldDraw = false := rfl

end Frame

end Inkproof.Web
