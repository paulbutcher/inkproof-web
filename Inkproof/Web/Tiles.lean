/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Core

namespace Inkproof.Web

open Inkproof.Core

/-- `Aggregate.foldTiles` with the tiles fetched in a monad. Only the tiles the range touches are fetched, one at a time, and `yield` runs between them so that a long range hands control back to the event loop instead of blocking it. -/
def foldTilesM {m : Type → Type} [Monad m] {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n)
    (fetch : Nat → m (Array M)) (yield : m Unit) (lo hi : Nat) : m M :=
  if lo < hi then do
    let stop := min hi ((lo / n + 1) * n)
    let tile ← fetch (lo / n)
    let here := Aggregate.foldRange tile (lo - lo / n * n) (stop - lo / n * n)
    yield
    let rest ← foldTilesM n hn fetch yield stop hi
    pure (Aggregate.merge here rest)
  else pure Aggregate.empty
termination_by hi - lo
decreasing_by
  have := Nat.lt_mul_div_succ lo hn
  rw [Nat.mul_comm] at this
  omega

/-- Fetching tile by tile gives what Core computes from the same tiles. -/
theorem foldTilesM_id {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (tile : Nat → Array M) (lo hi : Nat) :
    foldTilesM (m := Id) n hn tile (pure ()) lo hi = Aggregate.foldTiles n hn tile lo hi := by
  rw [foldTilesM, Aggregate.foldTiles]
  by_cases h : lo < hi
  · have ih := foldTilesM_id n hn tile (min hi ((lo / n + 1) * n)) hi
    simp only [h, ite_true, bind_pure_comp] at ih ⊢
    simp [ih]
    rfl
  · simp [h]
    rfl
termination_by hi - lo
decreasing_by
  have := Nat.lt_mul_div_succ lo hn
  rw [Nat.mul_comm] at this
  omega

end Inkproof.Web
