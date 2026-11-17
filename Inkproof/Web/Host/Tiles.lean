/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Fetch
import Inkproof.Core
import Inkproof.Core.Proofs.Tile
import Inkproof.Web.Host.Console

namespace Inkproof.Web.Host
open Lasm.JS Inkproof.Core

/-- Resolves on a later turn of the event loop, so rendering and input are served in between. -/
def yieldToEventLoop : Async Unit := do
  let executor ← Function.ofSyncFn fun args => do
    if let some (Data.ref resolve _) := args[0]? then
      discard <| (← global).callMethod "setTimeout" #[toJS resolve, toJS 0] Nat
    return .undefined
  let promise ← (← (← global).get "Promise").new #[toJS executor]
  promise.await Unit

/-- The bytes `[start, start + len)` of the resource at `src`, or all of it when `range` is `none`. A server that ignores the `Range` header and answers 200 with the whole body has the range sliced out here. A failure is logged at warn with the URL and rethrown. -/
def fetchTile (src : String) (range : Option (Nat × Nat) := none) : Async ByteArray := do
  try
    let response ← match range with
      | none => Web.fetch (.usvString src)
      | some (start, len) =>
        Web.fetch (.usvString src)
          (some { headers := some (.record { entries := #[("Range", s!"bytes={start}-{start + len - 1}")] }) })
    unless (← response.ok) do
      throw (IO.userError s!"status {← response.status}")
    let body ← response.bytes
    match range with
    | some (start, len) =>
      if (← response.status) == 206 then
        if body.size == len then pure body
        else throw (IO.userError s!"{body.size} bytes for a range of {len}")
      else if start + len ≤ body.size then pure (body.extract start (start + len))
      else throw (IO.userError s!"a range of {len} bytes at {start} beyond {body.size}")
    | none => pure body
  catch e =>
    log .warn s!"fetching a tile failed: {e}" [("src", src)]
    throw e

/-- Decodes a fetched tile, logging a body `decode` rejects with the URL it came from and failing. -/
private def decodeTile {M : Type} (decode : ByteArray → Except String (Array M)) (src : String)
    (body : ByteArray) : Async (Array M) :=
  match decode body with
  | .ok tile => pure tile
  | .error e => do
    log .warn s!"fetching a tile failed: {e}" [("src", src)]
    throw (IO.userError e)

/-- Merge nodes `lo` to `hi - 1` of a level stored as tiles of `n` nodes at `url t`, decoding each tile body with `decode`. Fetching is asynchronous and control returns to the event loop after every tile, so the main thread is never blocked; a tile that fails is logged with its URL and fails the query. -/
def queryTiles {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (url : Nat → String)
    (decode : ByteArray → Except String (Array M)) (lo hi : Nat) : Async M :=
  Aggregate.foldTilesM n hn (fun t => do decodeTile decode (url t) (← fetchTile (url t))) yieldToEventLoop lo hi

/-- The aggregates of `cols` equal columns of the leaves `[lo, hi)` of a pyramid of `numLevels` levels with the given `branching`, whose tile `t` of level `k` is at `url k t`. Each tile is fetched once, with `fetchTile`, and control returns to the event loop after every tile; a tile that fails is logged with its URL and fails the query. -/
def queryColumns {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (branching numLevels : Nat)
    (url : Nat → Nat → String) (decode : ByteArray → Except String (Array M))
    (lo hi cols : Nat) : Async (Array M) :=
  Pyramid.columnsM n hn branching numLevels
    (fun k t => do decodeTile decode (url k t) (← fetchTile (url k t))) yieldToEventLoop lo hi cols

/-- The leaves `[lo, hi)` as one array from `parts`, each the leaves starting at the leaf index in its first component. Leaves no part covers are `Aggregate.empty`, so a gap contributes nothing. -/
def denseLeaves {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi : Nat) : Array M :=
  parts.foldl (init := Array.replicate (hi - lo) Aggregate.empty) fun acc (first, leaves) =>
    (leaves.zipIdx).foldl (init := acc) fun acc (leaf, i) =>
      if lo ≤ first + i ∧ first + i < hi then acc.setIfInBounds (first + i - lo) leaf else acc

theorem size_denseLeaves {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi : Nat) :
    (denseLeaves parts lo hi).size = hi - lo := by
  unfold denseLeaves
  refine Array.foldl_induction (motive := fun _ (acc : Array M) => acc.size = hi - lo) (by simp) ?_
  intro i acc h
  refine Array.foldl_induction (motive := fun _ (acc' : Array M) => acc'.size = hi - lo) h ?_
  intro j acc' h'
  split
  split <;> simp_all

private theorem foldl_leaves_empty {M : Type} [Aggregate M] (first lo hi j : Nat)
    (xs : List (M × Nat)) (acc : Array M)
    (hx : ∀ q ∈ xs, first + q.2 ≠ lo + j) (ha : ∀ x, acc[j]? = some x → x = Aggregate.empty) :
    ∀ x, (xs.foldl (fun acc (q : M × Nat) =>
      if lo ≤ first + q.2 ∧ first + q.2 < hi then acc.setIfInBounds (first + q.2 - lo) q.1 else acc) acc)[j]? = some x →
      x = Aggregate.empty := by
  induction xs generalizing acc with
  | nil => simpa using ha
  | cons q rest ih =>
    simp only [List.foldl_cons]
    apply ih
    · intro r hr; exact hx r (List.mem_cons_of_mem _ hr)
    · intro x h
      have hq := hx q (List.mem_cons_self ..)
      split at h
      · rename_i hc
        rw [Array.getElem?_setIfInBounds_ne (by omega)] at h
        exact ha x h
      · exact ha x h

/-- An entry of `denseLeaves` that no part covers is `Aggregate.empty`. The entry a part covers is that part's leaf (the last one, where parts overlap); stating it needs an ordering invariant on the overlapping writes, and the proof attempt did not close in a few tries, so it is covered by the browser test of the narrow path. -/
theorem denseLeaves_uncovered {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi j : Nat)
    (hj : j < hi - lo) (hc : ∀ p ∈ parts, ∀ i, i < p.2.size → p.1 + i ≠ lo + j) :
    (denseLeaves parts lo hi)[j]'(by have := size_denseLeaves parts lo hi; omega) = Aggregate.empty := by
  have key : ∀ (l : List (Nat × Array M)) (acc : Array M), (∀ p ∈ l, ∀ i, i < p.2.size → p.1 + i ≠ lo + j) →
      (∀ x, acc[j]? = some x → x = Aggregate.empty) →
      ∀ x, (l.foldl (fun acc (p : Nat × Array M) => (p.2.zipIdx).foldl (init := acc) fun acc (leaf, i) =>
        if lo ≤ p.1 + i ∧ p.1 + i < hi then acc.setIfInBounds (p.1 + i - lo) leaf else acc) acc)[j]? = some x →
        x = Aggregate.empty := by
    intro l
    induction l with
    | nil => intro acc _ ha; simpa using ha
    | cons p rest ih =>
      intro acc hl ha
      simp only [List.foldl_cons]
      apply ih
      · intro r hr; exact hl r (List.mem_cons_of_mem _ hr)
      · rw [← Array.foldl_toList]
        refine foldl_leaves_empty p.1 lo hi j _ acc ?_ ha
        intro q hq
        obtain ⟨_, hlt, _⟩ := Array.mem_zipIdx (Array.mem_toList_iff.mp hq)
        exact hl p (List.mem_cons_self ..) q.2 (by omega)
  have h := key parts.toList (Array.replicate (hi - lo) Aggregate.empty) (by simpa using hc)
    (by intro x hx; simp [Array.getElem?_replicate] at hx; exact hx.2.symm)
  have hlt : j < (denseLeaves parts lo hi).size := by have := size_denseLeaves parts lo hi; omega
  refine h _ ?_
  have e : (denseLeaves parts lo hi)[j]? = some (denseLeaves parts lo hi)[j] := Array.getElem?_eq_getElem hlt
  rw [← e]
  simp only [denseLeaves, Array.foldl_toList] at *

theorem denseLeaves_empty {M : Type} [Aggregate M] (lo hi : Nat) :
    denseLeaves (M := M) #[] lo hi = Array.replicate (hi - lo) Aggregate.empty := rfl

/-- Each of `cols` equal columns of the leaves `[lo, hi)` given as `parts` (`Pyramid.columns` over `denseLeaves`). -/
def columnsOfParts {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi cols : Nat) : Array M :=
  let leaves := denseLeaves parts lo hi
  Pyramid.columns (hi - lo + 1) (Nat.succ_pos _) 2 1 (fun _ t => leaves.extract (t * (hi - lo + 1)) ((t + 1) * (hi - lo + 1))) 0 (hi - lo) cols

/-- Columns over a pyramid stored from level `k0` up, with the leaves read separately. When every column spans at least `branching ^ k0` leaves, the columns come from the stored levels (`Pyramid.columnsFromM` over the level `k0` nodes that cover `[lo, hi)`); otherwise `raw lo hi` gives the leaves of `[lo, hi)` as parts for `columnsOfParts`. -/
def columnsRawM {M : Type} [Aggregate M] {m : Type → Type} [Monad m] (n : Nat) (hn : 0 < n)
    (branching numLevels k0 : Nat) (fetch : Nat → Nat → m (Array M)) (yield : m PUnit)
    (raw : Nat → Nat → m (Array (Nat × Array M))) (lo hi cols : Nat) : m (Array M) :=
  if cols * branching ^ k0 ≤ hi - lo then
    Pyramid.columnsFromM n hn branching numLevels fetch yield k0 (lo / branching ^ k0)
      ((hi + branching ^ k0 - 1) / branching ^ k0) cols
  else do
    pure (columnsOfParts (← raw lo hi) lo hi cols)

theorem columnsOfParts_eq {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi cols : Nat) :
    columnsOfParts parts lo hi cols =
      Pyramid.columns (hi - lo + 1) (Nat.succ_pos _) 2 1
        (fun _ t => (denseLeaves parts lo hi).extract (t * (hi - lo + 1)) ((t + 1) * (hi - lo + 1))) 0 (hi - lo) cols := rfl

theorem size_columnsOfParts {M : Type} [Aggregate M] (parts : Array (Nat × Array M)) (lo hi cols : Nat) :
    (columnsOfParts parts lo hi cols).size = cols :=
  Pyramid.size_columns ..

theorem columnsRawM_id {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (branching numLevels k0 : Nat)
    (tile : Nat → Nat → Array M) (raw : Nat → Nat → Array (Nat × Array M)) (lo hi cols : Nat) :
    columnsRawM (m := Id) n hn branching numLevels k0 (fun k t => pure (tile k t)) (pure PUnit.unit)
        (fun a b => pure (raw a b)) lo hi cols =
      if cols * branching ^ k0 ≤ hi - lo then
        Pyramid.columnsFrom n hn branching numLevels tile k0 (lo / branching ^ k0)
          ((hi + branching ^ k0 - 1) / branching ^ k0) cols
      else columnsOfParts (raw lo hi) lo hi cols := by
  unfold columnsRawM
  split
  · exact Pyramid.columnsFromM_id ..
  · rfl

/-- A run of leaves in a raw file: `len` bytes at `start` of `url`, decoding to leaves from leaf index `first`. -/
structure RawRange where
  url : String
  first : Nat
  start : Nat
  len : Nat

/-- `queryColumns` for a pyramid whose finest stored level is `k0`, with the leaves in raw files. Where every column spans at least `branching ^ k0` leaves the columns cover whole level `k0` nodes, fetched as in `queryColumns`. Narrower columns are merged from leaves: `source lo hi` lists the ranges holding the leaves `[lo, hi)`, each fetched with `fetchTile` by byte range and decoded with `decodeLeaves`; a leaf in no range is a gap. A range or tile that fails is logged with its URL and fails the query. -/
def queryColumnsFrom {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (branching numLevels k0 : Nat)
    (url : Nat → Nat → String) (decode : ByteArray → Except String (Array M))
    (source : Nat → Nat → Array RawRange) (decodeLeaves : ByteArray → Except String (Array M))
    (lo hi cols : Nat) : Async (Array M) :=
  columnsRawM n hn branching numLevels k0
    (fun k t => do decodeTile decode (url k t) (← fetchTile (url k t))) yieldToEventLoop
    (fun lo hi => do
      let mut parts := #[]
      for r in source lo hi do
        let leaves ← decodeTile decodeLeaves r.url (← fetchTile r.url (some (r.start, r.len)))
        parts := parts.push (r.first, leaves)
        yieldToEventLoop
      pure parts) lo hi cols

end Inkproof.Web.Host
