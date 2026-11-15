/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

/-- Console severities, least to most severe. -/
inductive Level where
  | debug | info | warn | error
  deriving DecidableEq, Repr

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

theorem Level.enabled_iff (t l : Level) : l.enabled t = true ↔ t.rank ≤ l.rank := by
  simp [enabled]

theorem Level.warn_enabled_by_default : Level.enabled .warn Level.defaultThreshold = true := rfl

theorem Level.info_disabled_by_default : Level.enabled .info Level.defaultThreshold = false := rfl

end Inkproof.Web
