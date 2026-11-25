/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Facet
import Inkproof.Scene.Palette

namespace Inkproof.Web

open Inkproof.Scene

/-- The `theme` attribute: a fixed theme, or the page's colour scheme. -/
inductive ChartTheme where
  | light
  | dark
  | auto
  deriving DecidableEq, Repr

namespace ChartTheme

/-- Validate the raw `theme` attribute. A missing attribute is no theme, which leaves the chart as the scene made it; an empty or unknown value is an error. -/
def parse : Option String → Except String (Option ChartTheme)
  | none => .ok none
  | some "light" => .ok (some .light)
  | some "dark" => .ok (some .dark)
  | some "auto" => .ok (some .auto)
  | some w => Facet.unknown "theme" w "light, dark or auto"

/-- The theme drawn, given whether the page prefers a dark colour scheme. -/
def resolve (prefersDark : Bool) : ChartTheme → Theme
  | .light => .light
  | .dark => .dark
  | .auto => if prefersDark then .dark else .light

theorem parse_none : parse none = .ok none := rfl

theorem parse_light : parse (some "light") = .ok (some .light) := rfl

theorem parse_dark : parse (some "dark") = .ok (some .dark) := rfl

theorem parse_auto : parse (some "auto") = .ok (some .auto) := rfl

theorem parse_unknown : ∃ e, parse (some "blue") = .error e := ⟨_, rfl⟩

theorem parse_empty : ∃ e, parse (some "") = .error e := ⟨_, rfl⟩

theorem resolve_light (p : Bool) : resolve p .light = .light := rfl

theorem resolve_dark (p : Bool) : resolve p .dark = .dark := rfl

theorem resolve_auto (p : Bool) : resolve p .auto = if p then .dark else .light := rfl

end ChartTheme

end Inkproof.Web
