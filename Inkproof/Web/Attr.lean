/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Log

namespace Inkproof.Web

/-- The validated attributes of a chart element. -/
structure ChartAttrs where
  src : String
  logLevel : Option Level
  deriving DecidableEq, Repr

/-- Validate the raw attribute values. A missing or empty `src`, or a `log-level` that names no level, is an error and never a default. -/
def ChartAttrs.parse (src logLevel : Option String) : Except String ChartAttrs := do
  let src ← match src with
    | none => throw "attribute src is missing"
    | some "" => throw "attribute src is empty"
    | some s => pure s
  let logLevel ← match logLevel with
    | none => pure none
    | some s => match Level.parse? s with
      | some l => pure (some l)
      | none => throw s!"attribute log-level is \"{s}\", expected debug, info, warn or error"
  return ⟨src, logLevel⟩

theorem ChartAttrs.parse_ok {s : String} (h : s ≠ "") (l : Option Level) :
    ChartAttrs.parse (some s) (l.map Level.name) = .ok ⟨s, l⟩ := by
  cases l <;> simp [parse, Level.parse?_name, bind, Except.bind, pure, Except.pure]

theorem ChartAttrs.parse_missing_src (l : Option String) :
    ∃ e, ChartAttrs.parse none l = .error e := ⟨_, rfl⟩

end Inkproof.Web
