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

end BoxConfig

/-- What a drag with one pointer does: pan the view or draw a box to zoom to, with shift swapping the two, or nothing, leaving the drag to the browser. -/
inductive DragMode where
  | pan
  | box
  | off
  deriving DecidableEq

namespace DragMode

/-- Whether a drag started with the shift key in the given state draws a box. -/
def boxes (m : DragMode) (shift : Bool) : Bool :=
  match m with
  | .pan => shift
  | .box => !shift
  | .off => false

/-- Whether a drag started with the shift key in the given state pans. -/
def pans (m : DragMode) (shift : Bool) : Bool :=
  match m with
  | .pan => !shift
  | .box => shift
  | .off => false

theorem pans_not_boxes (m : DragMode) (shift : Bool) (h : m ≠ .off) : m.pans shift = !m.boxes shift := by
  cases m <;> simp_all [pans, boxes]

theorem boxes_off (shift : Bool) : DragMode.off.boxes shift = false := rfl

theorem pans_off (shift : Bool) : DragMode.off.pans shift = false := rfl

theorem boxes_pan (shift : Bool) : DragMode.pan.boxes shift = shift := rfl

theorem boxes_box (shift : Bool) : DragMode.box.boxes shift = !shift := rfl

end DragMode

end Inkproof.Web
