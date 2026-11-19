/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Access

namespace Inkproof.Web

open Inkproof.Viewport

/-- A position in CSS pixels from the chart's top left, as a pointer event reports it. -/
abbrev Px := Float × Float

namespace Pointer

/-- The view's screen position for a position in the element: y grows upward in a view and downward on the page. -/
def toView (c : NavConfig) (p : Px) : Px := (p.1, c.view.y.length - p.2)

theorem toView_eq (c : NavConfig) (p : Px) : toView c p = (p.1, c.view.y.length - p.2) := rfl

/-- Whether a position lies over the plot, which is what a view's axes span. -/
def inside (c : NavConfig) (p : Px) : Bool :=
  0 ≤ p.1 && p.1 ≤ c.view.x.length && 0 ≤ p.2 && p.2 ≤ c.view.y.length

theorem inside_eq (c : NavConfig) (p : Px) :
    inside c p = (0 ≤ p.1 && p.1 ≤ c.view.x.length && 0 ≤ p.2 && p.2 ≤ c.view.y.length) := rfl

/-- The zoom factor of a wheel turn of `delta` pixels; scrolling down zooms out. -/
def wheelFactor (delta : Float) : Float := Float.exp (-delta / 500)

theorem wheelFactor_eq (delta : Float) : wheelFactor delta = Float.exp (-delta / 500) := rfl

/-- The factor by which two fingers have moved apart along one axis, or none when either gap is too small to measure. -/
def spread (old new : Float) : Float := if old < 1 || new < 1 then 1 else new / old

theorem spread_eq (old new : Float) : spread old new = if old < 1 || new < 1 then 1 else new / old := rfl

/-- The inputs for two fingers moving from `o₁ o₂` to `n₁ n₂`: zoom about the old midpoint by how far they spread on each axis, then drag by how far the midpoint moved. Positions are already in view coordinates. -/
def pinch (o₁ o₂ n₁ n₂ : Px) : List (Input Float) :=
  let ox := (o₁.1 + o₂.1) / 2
  let oy := (o₁.2 + o₂.2) / 2
  [.pinch ox oy (spread (o₂.1 - o₁.1).abs (n₂.1 - n₁.1).abs) (spread (o₂.2 - o₁.2).abs (n₂.2 - n₁.2).abs),
   .drag ((n₁.1 + n₂.1) / 2 - ox) ((n₁.2 + n₂.2) / 2 - oy)]

theorem pinch_eq (o₁ o₂ n₁ n₂ : Px) :
    pinch o₁ o₂ n₁ n₂ =
      [.pinch ((o₁.1 + o₂.1) / 2) ((o₁.2 + o₂.2) / 2) (spread (o₂.1 - o₁.1).abs (n₂.1 - n₁.1).abs)
        (spread (o₂.2 - o₁.2).abs (n₂.2 - n₁.2).abs),
       .drag ((n₁.1 + n₂.1) / 2 - (o₁.1 + o₂.1) / 2) ((n₁.2 + n₂.2) / 2 - (o₁.2 + o₂.2) / 2)] := rfl

/-- A box drag shorter than this, in pixels, on either axis is a click, not a selection. -/
def minBox : Float := 4

/-- The box zoom for a drag between two positions, if it is big enough. -/
def box (c : NavConfig) (a b : Px) : Option (Input Float) :=
  if (b.1 - a.1).abs < minBox || (b.2 - a.2).abs < minBox then none
  else
    let a := toView c a
    let b := toView c b
    some (.box a.1 a.2 b.1 b.2)

theorem box_none (c : NavConfig) (a b : Px) (h : (b.1 - a.1).abs < minBox) : box c a b = none := by
  simp [box, h]

theorem box_some (c : NavConfig) (a b : Px) (h : ¬((b.1 - a.1).abs < minBox || (b.2 - a.2).abs < minBox) = true) :
    box c a b = some (.box (toView c a).1 (toView c a).2 (toView c b).1 (toView c b).2) := by
  simp [box, h]

end Pointer

namespace Nav

/-- The state after a view input, which is how a pointer gesture reaches the view. -/
def input (c : NavConfig) (n : Nav) (i : Input Float) : Nav := { n with view := View.step c.view n.view i }

theorem input_eq (c : NavConfig) (n : Nav) (i : Input Float) :
    n.input c i = { n with view := View.step c.view n.view i } := rfl

theorem input_key (c : NavConfig) (n : Nav) (k : Key) : n.input c (.key k) = n.apply c (.view k) := rfl

end Nav

end Inkproof.Web
