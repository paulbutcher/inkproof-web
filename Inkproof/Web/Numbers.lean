/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Facet

namespace Inkproof.Web

namespace Numbers

open Inkproof.Axis

private structure Choices where
  locale : Option Locale := none
  precision : Option Nat := none
  compact : Option (List String) := none

private def forms : String :=
  "en, de, fr, compact or a number of decimals such as 2dp"

private def decimals (word : String) : Option Nat :=
  if word.endsWith "dp" then (word.dropEnd 2).toString.toNat? else none

private def choose (c : Choices) (w : String) : Except String Choices :=
  match w with
  | "en" => (Facet.pick "number-format" "locale" w c.locale Locale.en).map ({ c with locale := · })
  | "de" => (Facet.pick "number-format" "locale" w c.locale Locale.de).map ({ c with locale := · })
  | "fr" => (Facet.pick "number-format" "locale" w c.locale Locale.fr).map ({ c with locale := · })
  | "compact" => (Facet.pick "number-format" "compact notation" w c.compact NumberFormat.short).map ({ c with compact := · })
  | _ =>
    match decimals w with
    | some n => (Facet.pick "number-format" "precision" w c.precision n).map ({ c with precision := · })
    | none => Facet.unknown "number-format" w forms

/-- Validate the raw `number-format` attribute: a list of words in any order, each kind at most once. A missing or empty attribute is no format, which writes numbers as `showFloat` does. `en` (the default), `de` or `fr` set the separators, `compact` writes 1200 as 1.2k, and a number of decimals such as `2dp` fixes them, where otherwise as few are shown as tell the values apart. -/
def parse : Option String → Except String (Option NumberFormat)
  | none => .ok none
  | some s =>
    ((Legend.words s).foldlM choose {}).map fun c =>
      if (Legend.words s).isEmpty then none
      else some { locale := c.locale.getD Locale.en, precision := c.precision, compact := c.compact.getD [] }

theorem parse_none : parse none = .ok none := rfl

theorem parse_empty : parse (some "") = .ok none := rfl

theorem parse_de : parse (some "de") = .ok (some { locale := Locale.de, precision := none, compact := [] }) := by
  rfl

theorem parse_compact : parse (some "fr compact") = .ok (some { locale := Locale.fr, precision := none, compact := NumberFormat.short }) := by
  rfl

-- Precision words such as `2dp` go through `String.toNat?`, which `rfl` and `decide` cannot unfold, so no equation is stated for them; tests cover them.

end Numbers

end Inkproof.Web
