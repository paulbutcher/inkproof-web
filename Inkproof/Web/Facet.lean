/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Legend

namespace Inkproof.Web

namespace Facet

/-- Record `new` as the choice of `kind` in attribute `attr`; a second word for the same kind is an error. -/
def pick {α : Type} (attr kind word : String) (old : Option α) (new : α) : Except String (Option α) :=
  match old with
  | none => .ok (some new)
  | some _ => .error s!"attribute {attr} has two words for the {kind}, one of them \"{word}\""

theorem pick_none {α : Type} (attr kind word : String) (new : α) : pick attr kind word none new = .ok (some new) := rfl

theorem pick_some {α : Type} (attr kind word : String) (old new : α) :
    ∃ e, pick attr kind word (some old) new = .error e := ⟨_, rfl⟩

/-- The error for a word that names no choice of attribute `attr`. -/
def unknown {α : Type} (attr word expected : String) : Except String α :=
  .error s!"attribute {attr} has the unknown word \"{word}\", expected {expected}"

theorem unknown_error {α : Type} (attr word expected : String) : ∃ e, (unknown attr word expected : Except String α) = .error e := ⟨_, rfl⟩

/-- The pixels of a magnitude word such as `8px`; none for anything else. -/
def pixels (word : String) : Option Nat :=
  if word.endsWith "px" then (word.dropEnd 2).toString.toNat? else none

theorem pixels_none (word : String) (h : word.endsWith "px" = false) : pixels word = none := by
  simp [pixels, h]

theorem pixels_of (word : String) (h : word.endsWith "px" = true) : pixels word = (word.dropEnd 2).toString.toNat? := by
  simp [pixels, h]

/-- The positive pixels of a magnitude word; zero is an error. -/
def positive (attr kind word : String) (n : Nat) : Except String Nat :=
  if n == 0 then .error s!"attribute {attr} has {word} for the {kind}, expected a positive number of pixels" else .ok n

theorem positive_zero (attr kind word : String) : ∃ e, positive attr kind word 0 = .error e := ⟨_, rfl⟩

theorem positive_succ (attr kind word : String) (n : Nat) : positive attr kind word (n + 1) = .ok (n + 1) := by
  simp [positive]

end Facet

end Inkproof.Web
