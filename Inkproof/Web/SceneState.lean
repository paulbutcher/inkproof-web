/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Gpu.Retained

namespace Inkproof.Web

open Inkproof.Gpu

/-- What a chart keeps between frames: the buffers on the GPU and the draws recorded for the layers drawn from them, the context generation they were uploaded under, and whether a frame has been drawn from them. -/
structure SceneState where
  retained : Retained
  generation : Nat
  drawn : Bool

namespace SceneState

/-- The state of a chart that has uploaded nothing under `generation`, numbering its buffers from `base`. -/
def fresh (base generation : Nat) : SceneState := ⟨⟨{ next := base }, []⟩, generation, false⟩

/-- The state to build the next frame from: `s` while it was built under `generation`, otherwise one for a fresh context, since a lost context discarded the buffers. -/
def current (base generation : Nat) (s : Option SceneState) : SceneState :=
  match s with
  | some s => if s.generation == generation then s else fresh base generation
  | none => fresh base generation

/-- The state after a frame that left the buffers and recorded draws in `retained`. -/
def drew (s : SceneState) (retained : Retained) : SceneState := { s with retained, drawn := true }

theorem current_none (base generation : Nat) : current base generation none = fresh base generation := rfl

theorem current_same (base : Nat) (s : SceneState) : current base s.generation (some s) = s := by
  simp [current]

theorem current_stale (base generation : Nat) (s : SceneState) (h : s.generation ≠ generation) :
    current base generation (some s) = fresh base generation := by
  simp [current, h]

theorem current_generation (base generation : Nat) (s : Option SceneState) :
    (current base generation s).generation = generation := by
  unfold current
  split <;> try rfl
  split <;> simp_all [fresh]

theorem fresh_undrawn (base generation : Nat) :
    (fresh base generation).drawn = false ∧ (fresh base generation).retained.cache.entries = [] ∧
      (fresh base generation).retained.cache.next = base ∧ (fresh base generation).retained.streams = [] :=
  ⟨rfl, rfl, rfl, rfl⟩

theorem drew_retained (s : SceneState) (r : Retained) : (s.drew r).retained = r ∧ (s.drew r).drawn = true := ⟨rfl, rfl⟩

theorem drew_generation (s : SceneState) (r : Retained) : (s.drew r).generation = s.generation := rfl

end SceneState

end Inkproof.Web
