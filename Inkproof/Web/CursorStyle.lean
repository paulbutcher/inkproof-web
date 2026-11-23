/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Cursor
import Inkproof.Web.Facet
import Inkproof.Web.Markers

namespace Inkproof.Web

/-- What a chart draws at the cursor: its lines, dotted or solid, and the markers on its series. -/
structure CursorStyle where
  lines : CursorMode := .off
  dotted : Bool := false
  markers : MarkerMode := .off
  marker : MarkerStyle := {}

namespace CursorStyle

private structure Choices where
  lines : Option CursorMode := none
  dotted : Bool := false
  markers : Option MarkerMode := none
  filled : Option Bool := none
  size : Option Nat := none

private def forms : String :=
  "off, x, y, xy, dotted, markers, nearest-marker, filled, outline or a marker size in pixels such as 6px"

private def choose (c : Choices) (w : String) : Except String Choices :=
  match w with
  | "x" => (Facet.pick "cursor" "lines" w c.lines .x).map ({ c with lines := · })
  | "y" => (Facet.pick "cursor" "lines" w c.lines .y).map ({ c with lines := · })
  | "xy" => (Facet.pick "cursor" "lines" w c.lines .xy).map ({ c with lines := · })
  | "dotted" => .ok { c with dotted := true }
  | "markers" => (Facet.pick "cursor" "markers" w c.markers .all).map ({ c with markers := · })
  | "nearest-marker" => (Facet.pick "cursor" "markers" w c.markers .nearest).map ({ c with markers := · })
  | "filled" => (Facet.pick "cursor" "marker fill" w c.filled true).map ({ c with filled := · })
  | "outline" => (Facet.pick "cursor" "marker fill" w c.filled false).map ({ c with filled := · })
  | _ =>
    match Facet.pixels w with
    | some n => do
      let n ← Facet.positive "cursor" "marker size" w n
      (Facet.pick "cursor" "marker size" w c.size n).map ({ c with size := · })
    | none => Facet.unknown "cursor" w forms

private def finish (c : Choices) : CursorStyle :=
  { lines := c.lines.getD .off, dotted := c.dotted, markers := c.markers.getD .off,
    marker := { size := (c.size.getD 6).toFloat, filled := c.filled.getD true } }

/-- Validate the raw `cursor` attribute: a list of words in any order, each kind at most once. A missing attribute or `off` draws nothing. `x`, `y` or `xy` draw cursor lines; `dotted` draws them dotted; `markers` or `nearest-marker` draw a marker on every series at the cursor or only on the one nearest the pointer; `filled` (the default) or `outline` and a size in pixels such as `6px` (the default) say how a marker looks. -/
def parse : Option String → Except String CursorStyle
  | none | some "off" => .ok {}
  | some s => (Legend.words s).foldlM choose {} |>.map finish

theorem parse_none : ∃ c, parse none = .ok c ∧ c.lines = .off ∧ c.dotted = false ∧ c.markers = .off := ⟨_, rfl, rfl, rfl, rfl⟩

theorem parse_off : ∃ c, parse (some "off") = .ok c ∧ c.lines = .off ∧ c.dotted = false ∧ c.markers = .off := ⟨_, rfl, rfl, rfl, rfl⟩

theorem parse_xy : ∃ c, parse (some "xy dotted") = .ok c ∧ c.lines = .xy ∧ c.dotted = true := ⟨_, rfl, rfl, rfl⟩

theorem parse_markers : ∃ c, parse (some "nearest-marker outline") = .ok c ∧ c.markers = .nearest ∧
    c.marker.filled = false := ⟨_, rfl, rfl, rfl⟩

theorem parse_two_lines : ∃ e, parse (some "x y") = .error e := ⟨_, rfl⟩

-- No theorem covers the size words (`6px`): `rfl` and `simp` do not reduce `String.dropEnd` and `toNat?` on a literal, so the native test `facetSizeCase` checks them.

end CursorStyle

end Inkproof.Web
