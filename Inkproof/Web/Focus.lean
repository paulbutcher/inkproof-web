/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Facet
import Inkproof.Web.Probe

namespace Inkproof.Web

/-- How a chart dims the series away from the pointer: the opacity of the others, and how near in pixels a point must be for its series to keep full opacity. -/
structure Focus where
  alpha : Float := 0.3
  proximity : Float := 5

namespace Focus

private structure Choices where
  alpha : Option Float := none
  proximity : Option Nat := none

private def forms : String :=
  "off, an opacity from 0 to 1 such as 0.3, or a proximity in pixels such as 5px"

/-- The opacity of a word such as `0.3` or `1`: decimal digits with at most a fractional part, from 0 to 1. -/
def opacity (word : String) : Option Float :=
  match word.splitOn "." with
  | [whole] => whole.toNat?.bind fun n => if n ≤ 1 then some n.toFloat else none
  | [whole, frac] =>
    match whole.toNat?, frac.toNat? with
    | some n, some f =>
      if frac.all Char.isDigit && n * 10 ^ frac.length + f ≤ 10 ^ frac.length
      then some ((n * 10 ^ frac.length + f).toFloat / (10 ^ frac.length).toFloat) else none
    | _, _ => none
  | _ => none

private def choose (c : Choices) (w : String) : Except String Choices :=
  match Facet.pixels w with
  | some n => do
    let n ← Facet.positive "focus" "proximity" w n
    (Facet.pick "focus" "proximity" w c.proximity n).map ({ c with proximity := · })
  | none =>
    match opacity w with
    | some a => (Facet.pick "focus" "opacity" w c.alpha a).map ({ c with alpha := · })
    | none => Facet.unknown "focus" w forms

/-- Validate the raw `focus` attribute: a missing one or `off` dims nothing. Otherwise a list of words in any order, each kind at most once, with the defaults for what is not named (an empty attribute is all defaults): an opacity from 0 to 1 for the series away from the pointer (0.3) and a proximity in pixels such as `5px` (the default) within which a point focuses its series. -/
def parse : Option String → Except String (Option Focus)
  | none | some "off" => .ok none
  | some s => ((Legend.words s).foldlM choose {}).map fun c =>
      some { alpha := c.alpha.getD 0.3, proximity := (c.proximity.getD 5).toFloat }

theorem parse_none : parse none = .ok none := rfl

theorem parse_off : parse (some "off") = .ok none := rfl

theorem parse_empty : ∃ f, parse (some "") = .ok (some f) ∧ f.alpha = 0.3 ∧ f.proximity = 5 := ⟨_, rfl, rfl, rfl⟩

-- No theorem covers the words `0.3` and `5px`: `String.splitOn`, `toNat?` and `dropEnd` do not reduce on a literal, so the native test `focusParseCase` checks them.

/-- The series that keeps full opacity: that of the point of `traces` nearest `(px, py)` in the plot's pixels, if it is within the proximity. -/
def nearestSeries (style : Focus) (traces : Array Trace) (px py : Float) : Option Nat :=
  (Nearest.find .plane traces px py).bind fun c =>
    if Metric.dist .plane px py c ≤ style.proximity * style.proximity then some c.series else none

theorem nearestSeries_eq (style : Focus) (traces : Array Trace) (px py : Float) :
    nearestSeries style traces px py = (Nearest.find .plane traces px py).bind fun c =>
      if Metric.dist .plane px py c ≤ style.proximity * style.proximity then some c.series else none := rfl

/-- The opacity of each of `count` series when `focused` keeps full opacity and the others have `alpha`; all are opaque when none is focused. -/
def alphas (count : Nat) (alpha : Float) (focused : Option Nat) : Array Float :=
  Array.ofFn (n := count) fun i => match focused with
    | some f => if i.val = f then 1 else alpha
    | none => 1

theorem alphas_getD (count : Nat) (alpha : Float) (focused : Option Nat) (i : Nat) (h : i < count) :
    (alphas count alpha focused).getD i 1 = match focused with | some f => if i = f then 1 else alpha | none => 1 := by
  simp [alphas, Array.getD_eq_getD_getElem?, h]

theorem alphas_size (count : Nat) (alpha : Float) (focused : Option Nat) : (alphas count alpha focused).size = count := by
  simp [alphas]

end Focus

end Inkproof.Web
