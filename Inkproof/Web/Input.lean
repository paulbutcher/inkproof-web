/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Box
import Inkproof.Web.Select

namespace Inkproof.Web

/-- When the wheel zooms a chart: always, only with Ctrl or Meta held (a plain wheel scrolls the page), or never. -/
inductive WheelMode where
  | zoom
  | ctrl
  | off
  deriving DecidableEq

namespace WheelMode

/-- Whether a wheel event with the given modifiers zooms. -/
def zooms (m : WheelMode) (ctrl cmd : Bool) : Bool :=
  match m with
  | .zoom => true
  | .ctrl => ctrl || cmd
  | .off => false

theorem zooms_zoom (ctrl cmd : Bool) : WheelMode.zoom.zooms ctrl cmd = true := rfl

theorem zooms_ctrl (ctrl cmd : Bool) : WheelMode.ctrl.zooms ctrl cmd = (ctrl || cmd) := rfl

theorem zooms_off (ctrl cmd : Bool) : WheelMode.off.zooms ctrl cmd = false := rfl

end WheelMode

/-- Whether a chart uses touch gestures (a finger drag and a two-finger pinch) or leaves them to the browser. -/
inductive TouchMode where
  | on
  | off
  deriving DecidableEq

namespace TouchMode

end TouchMode

/-- The touch gestures a chart takes from the browser, as a CSS `touch-action` value. -/
inductive TouchAction where
  | auto
  | panY
  | panXY
  | none
  deriving DecidableEq

namespace TouchAction

def css : TouchAction → String
  | .auto => "auto"
  | .panY => "pan-y"
  | .panXY => "pan-x pan-y"
  | .none => "none"

theorem css_auto : css .auto = "auto" := rfl

theorem css_panY : css .panY = "pan-y" := rfl

theorem css_panXY : css .panXY = "pan-x pan-y" := rfl

theorem css_none : css .none = "none" := rfl

/-- What a chart blocks of the browser's touch handling: nothing without a view or with touch off; vertical scrolling is left to the page when the chart's only touch use is a horizontal drag (selecting a range), and everything when it selects a rectangle; one-finger scrolling is left to it when only the pinch is used; everything when a finger drag pans or boxes. -/
def of (hasView : Bool) (touch : TouchMode) (drag : DragMode) (select : SelectMode) : TouchAction :=
  if !hasView || touch == .off then .auto
  else if select == .x then .panY
  else if select == .xy then .none
  else if drag == .off then .panXY
  else .none

theorem of_no_view (touch : TouchMode) (drag : DragMode) (select : SelectMode) : of false touch drag select = .auto := rfl

theorem of_touch_off (drag : DragMode) (select : SelectMode) : of true .off drag select = .auto := by
  simp [of]

theorem of_select (drag : DragMode) : of true .on drag .x = .panY := by
  simp [of]

theorem of_select_xy (drag : DragMode) : of true .on drag .xy = .none := by
  simp [of]

theorem of_drag_off : of true .on .off .off = .panXY := by
  simp [of]

theorem of_drag (drag : DragMode) (h : drag ≠ .off) : of true .on drag .off = .none := by
  simp [of, h]

end TouchAction

end Inkproof.Web
