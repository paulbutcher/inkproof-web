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

/-- Validate the raw `wheel` value. A missing one is `zoom`. -/
def parse : Option String → Except String WheelMode
  | none | some "zoom" => .ok .zoom
  | some "ctrl" => .ok .ctrl
  | some "off" => .ok .off
  | some s => .error s!"attribute wheel is \"{s}\", expected zoom, ctrl or off"

theorem parse_none : parse none = .ok .zoom := rfl

theorem parse_ctrl : parse (some "ctrl") = .ok .ctrl := rfl

theorem parse_off : parse (some "off") = .ok .off := rfl

theorem parse_invalid (s : String) (h : s ≠ "zoom" ∧ s ≠ "ctrl" ∧ s ≠ "off") : ∃ e, parse (some s) = .error e := by
  obtain ⟨h₁, h₂, h₃⟩ := h
  unfold parse
  split <;> first | exact ⟨_, rfl⟩ | simp_all

end WheelMode

/-- Whether a chart uses touch gestures (a finger drag and a two-finger pinch) or leaves them to the browser. -/
inductive TouchMode where
  | on
  | off
  deriving DecidableEq

namespace TouchMode

/-- Validate the raw `touch` value. A missing one is `on`. -/
def parse : Option String → Except String TouchMode
  | none | some "on" => .ok .on
  | some "off" => .ok .off
  | some s => .error s!"attribute touch is \"{s}\", expected on or off"

theorem parse_none : parse none = .ok .on := rfl

theorem parse_off : parse (some "off") = .ok .off := rfl

theorem parse_invalid (s : String) (h : s ≠ "on" ∧ s ≠ "off") : ∃ e, parse (some s) = .error e := by
  obtain ⟨h₁, h₂⟩ := h
  unfold parse
  split <;> first | exact ⟨_, rfl⟩ | simp_all

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

/-- What a chart blocks of the browser's touch handling: nothing without a view or with touch off; vertical scrolling is left to the page when the chart's only touch use is a horizontal drag (selecting a range); one-finger scrolling is left to it when only the pinch is used; everything when a finger drag pans or boxes. -/
def of (hasView : Bool) (touch : TouchMode) (drag : DragMode) (select : SelectMode) : TouchAction :=
  if !hasView || touch == .off then .auto
  else if select != .off then .panY
  else if drag == .off then .panXY
  else .none

theorem of_no_view (touch : TouchMode) (drag : DragMode) (select : SelectMode) : of false touch drag select = .auto := rfl

theorem of_touch_off (drag : DragMode) (select : SelectMode) : of true .off drag select = .auto := by
  simp [of]

theorem of_select (drag : DragMode) : of true .on drag .x = .panY := by
  simp [of]

theorem of_drag_off : of true .on .off .off = .panXY := by
  simp [of]

theorem of_drag (drag : DragMode) (h : drag ≠ .off) : of true .on drag .off = .none := by
  simp [of, h]

end TouchAction

end Inkproof.Web
