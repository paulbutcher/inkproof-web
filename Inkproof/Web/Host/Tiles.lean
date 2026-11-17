/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Fetch
import Inkproof.Core
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

/-- Merge nodes `lo` to `hi - 1` of a level stored as tiles of `n` nodes at `url t`, decoding each tile body with `decode`. Fetching is asynchronous and control returns to the event loop after every tile, so the main thread is never blocked; a tile that fails is logged with its URL and fails the query. -/
def queryTiles {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (url : Nat → String)
    (decode : ByteArray → Except String (Array M)) (lo hi : Nat) : Async M :=
  Aggregate.foldTilesM n hn (fun t => do
    match decode (← fetchTile (url t)) with
    | .ok tile => pure tile
    | .error e =>
      log .warn s!"fetching a tile failed: {e}" [("src", url t)]
      throw (IO.userError e)) yieldToEventLoop lo hi

end Inkproof.Web.Host
