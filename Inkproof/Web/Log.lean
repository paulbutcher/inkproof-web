/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

/-- Console severities, least to most severe. -/
inductive Level where
  | debug | info | warn | error
  deriving DecidableEq, Repr, Inhabited

/-- Severity rank. -/
def Level.rank : Level → Nat
  | .debug => 0
  | .info => 1
  | .warn => 2
  | .error => 3

/-- The default threshold: warnings and errors only. -/
def Level.defaultThreshold : Level := .warn

/-- Whether a message at this level is emitted under a threshold. -/
def Level.enabled (l threshold : Level) : Bool := threshold.rank ≤ l.rank

/-- The name used in attributes and in console lines. -/
def Level.name : Level → String
  | .debug => "debug"
  | .info => "info"
  | .warn => "warn"
  | .error => "error"

/-- The level an attribute value names, if it names one. -/
def Level.parse? (s : String) : Option Level :=
  [Level.debug, .info, .warn, .error].find? (·.name == s)

theorem Level.name_eq (l : Level) :
    l.name = match l with | .debug => "debug" | .info => "info" | .warn => "warn" | .error => "error" := by
  cases l <;> rfl

theorem Level.parse?_name (l : Level) : Level.parse? l.name = some l := by
  cases l <;> rfl

theorem Level.parse?_none {s : String} (h : s ∉ ["debug", "info", "warn", "error"]) :
    Level.parse? s = none := by
  simp only [parse?, List.find?_eq_none]
  intro l hl
  have : l.name ≠ s := by
    intro e
    apply h
    subst e
    cases l <;> simp [name]
  simpa using this

/-- One console line: the severity, the message, then each deciding value as `key=value`. -/
def formatLine (l : Level) (message : String) (values : List (String × String)) : String :=
  " ".intercalate (s!"[inkproof {l.name}] {message}" :: values.map fun (k, v) => s!"{k}={v}")

theorem formatLine_eq (l : Level) (m : String) (values : List (String × String)) :
    formatLine l m values = " ".intercalate (s!"[inkproof {l.name}] {m}" :: values.map fun (k, v) => s!"{k}={v}") := rfl

theorem formatLine_nil (l : Level) (m : String) : formatLine l m [] = s!"[inkproof {l.name}] {m}" := by
  simp [formatLine]

theorem Level.enabled_iff (t l : Level) : l.enabled t = true ↔ t.rank ≤ l.rank := by
  simp [enabled]

theorem Level.warn_enabled_by_default : Level.enabled .warn Level.defaultThreshold = true := rfl

theorem Level.info_disabled_by_default : Level.enabled .info Level.defaultThreshold = false := rfl

end Inkproof.Web
