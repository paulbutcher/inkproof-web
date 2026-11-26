/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Gpu.Frame
import Inkproof.Scene.Palette
import Inkproof.Scene.Scale

namespace Inkproof.Web

open Inkproof

/-- The sizes of a chart's canvas: in CSS pixels, and in the device pixels of its backing store. -/
structure Pixels where
  css : Nat × Nat
  backing : Nat × Nat
  /-- The theme the chart's `theme` attribute names, if it has one. -/
  theme : Option Scene.Theme := none

namespace Pixels

/-- The colour the chart is drawn on: the theme's, else `default`. -/
def background (p : Pixels) (default : Scene.Color := ⟨255, 255, 255, 255⟩) : Scene.Color := p.theme.elim default (·.background)

theorem background_eq (p : Pixels) (default : Scene.Color) : p.background default = p.theme.elim default (·.background) := rfl

/-- How many device pixels make a CSS pixel across the canvas. -/
def ratio (p : Pixels) : Rat := if p.css.1 = 0 then 1 else (p.backing.1 : Rat) / p.css.1

theorem ratio_eq (p : Pixels) : p.ratio = if p.css.1 = 0 then 1 else (p.backing.1 : Rat) / p.css.1 := rfl

/-- The wire bytes of a frame of `list`, laid out in CSS pixels, for the canvas's backing store: the list is scaled by the device pixel ratio so its clips, strokes and markers match the canvas. -/
def frameBytes (p : Pixels) (list : Scene.DisplayList) (bg : Scene.Color) : ByteArray :=
  Gpu.strokeFrameBytes p.backing.1 p.backing.2 (list.scale p.ratio) bg

theorem frameBytes_eq (p : Pixels) (list : Scene.DisplayList) (bg : Scene.Color) :
    p.frameBytes list bg = Gpu.strokeFrameBytes p.backing.1 p.backing.2 (list.scale p.ratio) bg := rfl

end Pixels

end Inkproof.Web
