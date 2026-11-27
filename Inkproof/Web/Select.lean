/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Viewport.Selection
import Inkproof.Viewport.View

namespace Inkproof.Web

open Inkproof.Viewport

/-- Whether a drag on the chart edits a selected x range, or a rectangle of x and y ranges, instead of changing the chart's view. -/
inductive SelectMode where
  | off
  | x
  | xy
  deriving DecidableEq

namespace SelectMode

/-- Whether the selection has a y range. -/
def hasY : SelectMode → Bool
  | .xy => true
  | _ => false

theorem hasY_xy : hasY .xy = true := rfl

theorem hasY_x : hasY .x = false := rfl

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

/-- The selection settings for the y range of a plot, as `config` is for the x range. -/
def configY (c : ViewConfig Float) : Selection.Config Float :=
  let domain := (View.home c).y
  let unit := domain.span / c.y.length
  { domain, minWidth := minPixels * unit, tolerance := grabPixels * unit }

theorem configY_domain (c : ViewConfig Float) : (configY c).domain = (View.home c).y := rfl

theorem configY_minWidth (c : ViewConfig Float) :
    (configY c).minWidth = minPixels * ((View.home c).y.span / c.y.length) := rfl

theorem configY_tolerance (c : ViewConfig Float) :
    (configY c).tolerance = grabPixels * ((View.home c).y.span / c.y.length) := rfl

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

/-- The view `view` shows when it follows a rectangle: the band's x range and the other band's y range. -/
def shownXY (view : View Float) (bx by_ : Selection.Band Float) : View Float :=
  { view with x := bx.toInterval, y := by_.toInterval }

theorem shownXY_x (view : View Float) (bx by_ : Selection.Band Float) : (shownXY view bx by_).x = bx.toInterval := rfl

theorem shownXY_y (view : View Float) (bx by_ : Selection.Band Float) : (shownXY view bx by_).y = by_.toInterval := rfl

/-- The y band that `view`'s y range covers, if it is tall enough to be one. -/
def followingY (c : ViewConfig Float) (view : View Float) : Option (Selection.Band Float) :=
  Selection.ofInterval (configY c) view.y

theorem followingY_eq (c : ViewConfig Float) (view : View Float) :
    followingY c view = Selection.draw (configY c) view.y.start (view.y.start + view.y.span) := rfl

/-- The vertical pixel extent from the top of the plot of `band` on a plot showing `view`. -/
def extentY (c : ViewConfig Float) (view : View Float) (band : Selection.Band Float) : Float × Float :=
  (c.y.length - view.y.toScreen c.y band.hi, c.y.length - view.y.toScreen c.y band.lo)

theorem extentY_eq (c : ViewConfig Float) (view : View Float) (band : Selection.Band Float) :
    extentY c view band = (c.y.length - view.y.toScreen c.y band.hi, c.y.length - view.y.toScreen c.y band.lo) := rfl

/-- The starts of a drag over a rectangle at data position `(px, py)`: a press outside it draws a new one, on an edge or corner resizes it along the axes grabbed, and in its body moves it. An axis that is not dragged is `none` and keeps its band. -/
def pressXY (cx cy : Selection.Config Float) (bx by_ : Option (Selection.Band Float)) (px py : Float) :
    Option (Selection.Drag Float) × Option (Selection.Drag Float) :=
  let gx := Selection.hit cx bx px
  let gy := Selection.hit cy by_ py
  let dx := Selection.press cx bx px
  let dy := Selection.press cy by_ py
  if gx == .outside || gy == .outside then (some (Selection.press cx none px), some (Selection.press cy none py))
  else if gx == .body && gy != .body then (none, some dy)
  else if gy == .body && gx != .body then (some dx, none)
  else (some dx, some dy)

theorem pressXY_eq (cx cy : Selection.Config Float) (bx by_ : Option (Selection.Band Float)) (px py : Float) :
    pressXY cx cy bx by_ px py =
      if Selection.hit cx bx px == .outside || Selection.hit cy by_ py == .outside then
        (some (Selection.press cx none px), some (Selection.press cy none py))
      else if Selection.hit cx bx px == .body && Selection.hit cy by_ py != .body then
        (none, some (Selection.press cy by_ py))
      else if Selection.hit cy by_ py == .body && Selection.hit cx bx px != .body then
        (some (Selection.press cx bx px), none)
      else (some (Selection.press cx bx px), some (Selection.press cy by_ py)) := rfl

theorem pressXY_outside (cx cy : Selection.Config Float) (px py : Float) :
    pressXY cx cy none none px py = (some (Selection.press cx none px), some (Selection.press cy none py)) := by
  simp [pressXY, Selection.hit]
  intro h
  exact absurd h (by decide)

/-- The rectangle after the drags reach `(px, py)`. An axis with no drag keeps its band; a rectangle drawn too thin on either axis is cleared. -/
def dragXY (cx cy : Selection.Config Float) (dx dy : Option (Selection.Drag Float))
    (bx by_ : Option (Selection.Band Float)) (px py : Float) :
    Option (Selection.Band Float) × Option (Selection.Band Float) :=
  let nx := match dx with | some d => Selection.Drag.at cx d px | none => bx
  let ny := match dy with | some d => Selection.Drag.at cy d py | none => by_
  match nx, ny with
  | some _, some _ => (nx, ny)
  | _, _ => (none, none)

theorem dragXY_eq (cx cy : Selection.Config Float) (dx dy : Option (Selection.Drag Float))
    (bx by_ : Option (Selection.Band Float)) (px py : Float) :
    dragXY cx cy dx dy bx by_ px py =
      match (match dx with | some d => Selection.Drag.at cx d px | none => bx),
            (match dy with | some d => Selection.Drag.at cy d py | none => by_) with
      | some x, some y => (some x, some y)
      | _, _ => (none, none) := by
  unfold dragXY
  cases (match dx with | some d => Selection.Drag.at cx d px | none => bx) <;>
    cases (match dy with | some d => Selection.Drag.at cy d py | none => by_) <;> rfl

theorem dragXY_keep (cx cy : Selection.Config Float) (bx by_ : Selection.Band Float) (px py : Float) :
    dragXY cx cy none none (some bx) (some by_) px py = (some bx, some by_) := rfl

end Select

end Inkproof.Web
