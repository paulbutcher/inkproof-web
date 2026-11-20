/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

namespace Inkproof.Web

namespace Group

/-- Validate the raw `group` value: a missing one means no group, and an empty one is an error. -/
def parse : Option String → Except String (Option String)
  | none => pure none
  | some "" => throw "attribute group is empty"
  | some name => pure (some name)

theorem parse_none : parse none = .ok none := rfl

theorem parse_name (name : String) (h : name ≠ "") : parse (some name) = .ok (some name) := by
  unfold parse
  split <;> simp_all <;> rfl

theorem parse_empty : ∃ e, parse (some "") = .error e := ⟨_, rfl⟩

end Group

end Inkproof.Web
