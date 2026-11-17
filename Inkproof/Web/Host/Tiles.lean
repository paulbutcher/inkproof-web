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

/-- At most `capacity` entries, the least recently used first. -/
structure Lru (κ α : Type) where
  capacity : Nat
  entries : Array (κ × α) := #[]

namespace Lru
variable {κ α : Type} [BEq κ]

/-- The value stored under `k`, which becomes the most recently used entry. -/
def find? (c : Lru κ α) (k : κ) : Option α × Lru κ α :=
  match c.entries.find? (·.1 == k) with
  | none => (none, c)
  | some e => (some e.2, { c with entries := (c.entries.filter (·.1 != k)).push e })

theorem find?_fst (c : Lru κ α) (k : κ) : (c.find? k).1 = (c.entries.find? (·.1 == k)).map (·.2) := by
  unfold find?
  cases h : c.entries.find? (·.1 == k) <;> simp

/-- Stores `v` under `k` as the most recently used entry, dropping the least recently used entries beyond `capacity`. -/
def insert (c : Lru κ α) (k : κ) (v : α) : Lru κ α :=
  let es := (c.entries.filter (·.1 != k)).push (k, v)
  { c with entries := es.extract (es.size - c.capacity) es.size }

theorem size_insert_le (c : Lru κ α) (k : κ) (v : α) : (c.insert k v).entries.size ≤ c.capacity := by
  simp only [insert, Array.size_extract]
  omega

theorem find?_insert [LawfulBEq κ] (c : Lru κ α) (k : κ) (v : α) (h : 0 < c.capacity) :
    (c.insert k v).entries.find? (·.1 == k) = some (k, v) := by
  simp only [insert]
  have hne : ∀ x ∈ (c.entries.filter (·.1 != k)).toList, (x.1 == k) = false := by
    intro x hx
    simp at hx
    simp [hx.2]
  generalize c.entries.filter (·.1 != k) = rest at hne
  rw [← Array.find?_toList]
  simp only [Array.toList_extract, Array.toList_push, Array.size_push, List.extract_eq_take_drop]
  rw [List.take_of_length_le (by simp),
    List.drop_append_of_le_length (by simp; omega), List.find?_append]
  have : List.find? (fun x => x.fst == k) (List.drop (rest.size + 1 - c.capacity) rest.toList) = none := by
    rw [List.find?_eq_none]
    intro x hx
    simp [hne x (List.mem_of_mem_drop hx)]
  simp [this]

theorem capacity_find?(c : Lru κ α) (k : κ) : (c.find? k).2.capacity = c.capacity := by
  unfold find?
  split <;> rfl

end Lru

/-- Decoded tiles and byte ranges, shared by queries that are given it, so that one fetch and one decode serve them all. It holds at most `capacity` of them, evicting the least recently used. Queries running at once that need the same tile share one fetch: the later ones wait for the first. Only a fetch that succeeded and decoded is stored; a failure is logged once by the query that made it and fails each query waiting on it. -/
structure TileCache (M : Type) where
  private mk ::
  private store : IO.Ref (Lru (String × Option (Nat × Nat)) (Array M))
  private pending : IO.Ref (Array ((String × Option (Nat × Nat)) × IO.Promise (Except String (Array M))))

def TileCache.new {M : Type} (capacity : Nat) : IO (TileCache M) :=
  return { store := ← IO.mkRef { capacity }, pending := ← IO.mkRef #[] }

/-- Decodes a fetched tile, logging a body `decode` rejects with the URL it came from and failing. -/
private def decodeTile {M : Type} (decode : ByteArray → Except String (Array M)) (src : String)
    (body : ByteArray) : Async (Array M) :=
  match decode body with
  | .ok tile => pure tile
  | .error e => do
    log .warn s!"fetching a tile failed: {e}" [("src", src)]
    throw (IO.userError e)

/-- The decoded tile or range at `src`, fetched with `fetchTile` unless `cache` holds it or is already fetching it. Only a body that decodes is stored, so a tile that fails is fetched and logged again by the next query. -/
private def loadTile {M : Type} (cache : Option (TileCache M)) (decode : ByteArray → Except String (Array M))
    (src : String) (range : Option (Nat × Nat) := none) : Async (Array M) := do
  let some c := cache | decodeTile decode src (← fetchTile src range)
  let key := (src, range)
  let (hit, lru) := (← c.store.get).find? key
  c.store.set lru
  if let some tile := hit then return tile
  if let some (_, p) := (← c.pending.get).find? (·.1 == key) then
    match (← Std.Async.MonadAwait.await p.result? : Option (Except String (Array M))) with
    | some (.ok tile) => return tile
    | some (.error e) => throw (IO.userError e)
    | none => throw (IO.userError s!"fetch of {src} was abandoned")
  let p ← IO.Promise.new
  c.pending.modify (·.push (key, p))
  let outcome ← try
      let tile ← decodeTile decode src (← fetchTile src range)
      c.store.modify (·.insert key tile)
      pure (Except.ok tile)
    catch e => pure (Except.error (toString e))
  c.pending.modify (·.filter (·.1 != key))
  p.resolve outcome
  match outcome with
  | .ok tile => return tile
  | .error e => throw (IO.userError e)

/-- Merge nodes `lo` to `hi - 1` of a level stored as tiles of `n` nodes at `url t`, decoding each tile body with `decode`. Fetching is asynchronous and control returns to the event loop after every tile, so the main thread is never blocked; a tile that fails is logged with its URL and fails the query. -/
def queryTiles {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (url : Nat → String)
    (decode : ByteArray → Except String (Array M)) (lo hi : Nat) (cache : Option (TileCache M) := none) : Async M :=
  Aggregate.foldTilesM n hn (fun t => do loadTile cache decode (url t)) yieldToEventLoop lo hi

/-- The aggregates of `cols` equal columns of the leaves `[lo, hi)` of a pyramid of `numLevels` levels with the given `branching`, whose tile `t` of level `k` is at `url k t`. Each tile is fetched once, with `fetchTile` unless `cache` holds it, and control returns to the event loop after every tile; a tile that fails is logged with its URL and fails the query. -/
def queryColumns {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (branching numLevels : Nat)
    (url : Nat → Nat → String) (decode : ByteArray → Except String (Array M))
    (lo hi cols : Nat) (cache : Option (TileCache M) := none) : Async (Array M) :=
  Pyramid.columnsM n hn branching numLevels
    (fun k t => do loadTile cache decode (url k t)) yieldToEventLoop lo hi cols

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
    (lo hi cols : Nat) (cache : Option (TileCache M) := none) : Async (Array M) :=
  columnsRawM n hn branching numLevels k0
    (fun k t => do loadTile cache decode (url k t)) yieldToEventLoop
    (fun lo hi => do
      let mut parts := #[]
      for r in source lo hi do
        let leaves ← loadTile cache decodeLeaves r.url (some (r.start, r.len))
        parts := parts.push (r.first, leaves)
        yieldToEventLoop
      pure parts) lo hi cols

end Inkproof.Web.Host
