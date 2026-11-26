/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Facet
import Inkproof.Web.Input

namespace Inkproof.Web

open Inkproof.Viewport

/-- How a chart answers the pointer: what the wheel, a touch and a drag do, which axes and how short a box drag zooms, and whether a drag selects a range. -/
structure Interaction where
  wheel : WheelMode := .zoom
  touch : TouchMode := .on
  drag : DragMode := .pan
  box : BoxConfig := {}
  select : SelectMode := .off
  dblclickReset : Bool := false

namespace Interaction

private structure Choices where
  wheel : Option WheelMode := none
  touch : Option TouchMode := none
  drag : Option DragMode := none
  axes : Option Gesture.Axes := none
  minDistance : Option Nat := none
  uni : Option Nat := none
  select : Option SelectMode := none
  dblclickReset : Option Bool := none

private def forms : String :=
  "wheel-zoom, wheel-ctrl, no-wheel, touch, no-touch, drag-pan, drag-box, no-drag, box-x, box-y, box-xy, box-auto, box-auto-uni-50px, select-x, dblclick-reset or a least box drag in pixels such as 4px"

private def choose (c : Choices) (w : String) : Except String Choices :=
  match w with
  | "wheel-zoom" => (Facet.pick "interaction" "wheel" w c.wheel .zoom).map ({ c with wheel := · })
  | "wheel-ctrl" => (Facet.pick "interaction" "wheel" w c.wheel .ctrl).map ({ c with wheel := · })
  | "no-wheel" => (Facet.pick "interaction" "wheel" w c.wheel .off).map ({ c with wheel := · })
  | "touch" => (Facet.pick "interaction" "touch" w c.touch .on).map ({ c with touch := · })
  | "no-touch" => (Facet.pick "interaction" "touch" w c.touch .off).map ({ c with touch := · })
  | "drag-pan" => (Facet.pick "interaction" "drag" w c.drag .pan).map ({ c with drag := · })
  | "drag-box" => (Facet.pick "interaction" "drag" w c.drag .box).map ({ c with drag := · })
  | "no-drag" => (Facet.pick "interaction" "drag" w c.drag .off).map ({ c with drag := · })
  | "box-x" => (Facet.pick "interaction" "box axes" w c.axes .x).map ({ c with axes := · })
  | "box-y" => (Facet.pick "interaction" "box axes" w c.axes .y).map ({ c with axes := · })
  | "box-xy" => (Facet.pick "interaction" "box axes" w c.axes .both).map ({ c with axes := · })
  | "box-auto" => (Facet.pick "interaction" "box axes" w c.axes .auto).map ({ c with axes := · })
  | "select-x" => (Facet.pick "interaction" "select" w c.select .x).map ({ c with select := · })
  | "dblclick-reset" => (Facet.pick "interaction" "double click" w c.dblclickReset true).map ({ c with dblclickReset := · })
  | _ =>
    match (if w.startsWith "box-auto-uni-" then Facet.pixels (w.drop 13).toString else none) with
    | some n => do
      let n ← Facet.positive "interaction" "box uni distance" w n
      let c ← (Facet.pick "interaction" "box axes" w c.axes .auto).map ({ c with axes := · })
      pure { c with uni := some n }
    | none =>
    match Facet.pixels w with
    | some n => do
      let n ← Facet.positive "interaction" "least box drag" w n
      (Facet.pick "interaction" "least box drag" w c.minDistance n).map ({ c with minDistance := · })
    | none => Facet.unknown "interaction" w forms

private def finish (c : Choices) : Interaction :=
  { wheel := c.wheel.getD .zoom, touch := c.touch.getD .on, drag := c.drag.getD .pan, select := c.select.getD .off, dblclickReset := c.dblclickReset.getD false,
    box := { axes := c.axes.getD .both, minDistance := (c.minDistance.map Nat.toFloat).getD Gesture.minBox, uni := c.uni.map Nat.toFloat } }

/-- Validate the raw `interaction` attribute: a list of words in any order, each kind at most once; one not named takes its default. `wheel-zoom`, `wheel-ctrl` (only with Ctrl or Meta held) or `no-wheel`; `touch` or `no-touch`, leaving finger gestures to the browser; `drag-pan`, `drag-box` or `no-drag`, which shift swaps; `box-x`, `box-y`, `box-xy` or `box-auto` for the axes a box drag zooms (`box-auto-uni-50px` is `box-auto`, but a drag under 50 pixels on both sides zooms both axes) and a size in pixels such as `4px` for the least such drag; `select-x`, for a drag that selects an x range; and `dblclick-reset`, for a double click that restores the home view. -/
def parse (s : Option String) : Except String Interaction :=
  ((Legend.words (s.getD "")).foldlM choose {}).map finish

theorem parse_none : ∃ i, parse none = .ok i ∧ i.wheel = .zoom ∧ i.touch = .on ∧ i.drag = .pan ∧ i.select = .off ∧
    i.box.axes = .both ∧ i.box.minDistance = Gesture.minBox := ⟨_, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem parse_wheel : ∃ i, parse (some "wheel-ctrl no-touch") = .ok i ∧ i.wheel = .ctrl ∧ i.touch = .off := ⟨_, rfl, rfl, rfl⟩

theorem parse_drag : ∃ i, parse (some "drag-box box-x select-x") = .ok i ∧ i.drag = .box ∧ i.box.axes = .x ∧
    i.select = .x := ⟨_, rfl, rfl, rfl, rfl⟩

theorem parse_dblclick : ∃ i, parse (some "dblclick-reset") = .ok i ∧ i.dblclickReset = true ∧ (parse none).toOption.map (·.dblclickReset) = some false :=
  ⟨_, rfl, rfl, rfl⟩

theorem parse_two_wheels : ∃ e, parse (some "wheel-zoom no-wheel") = .error e := ⟨_, rfl⟩

theorem parse_repeated : ∃ e, parse (some "no-drag no-drag") = .error e := ⟨_, rfl⟩

-- No theorem covers the size words (`4px`): `rfl` and `simp` do not reduce `String.dropEnd` and `toNat?` on a literal, so the native test `facetSizeCase` checks them.

end Interaction

end Inkproof.Web
