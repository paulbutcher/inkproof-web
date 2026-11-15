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

/-- Merge nodes `lo` to `hi - 1` of a level stored as tiles of `n` nodes at `url t`, decoding each tile body with `decode`. Fetching is asynchronous and control returns to the event loop after every tile, so the main thread is never blocked; a tile that fails is logged with its URL and fails the query. -/
def queryTiles {M : Type} [Aggregate M] (n : Nat) (hn : 0 < n) (url : Nat → String)
    (decode : ByteArray → Except String (Array M)) (lo hi : Nat) : Async M :=
  Aggregate.foldTilesM n hn (fun t => do
    let src := url t
    try
      let response ← Web.fetch (.usvString src)
      unless (← response.ok) do
        throw (IO.userError s!"status {← response.status}")
      match decode (← response.bytes) with
      | .ok tile => pure tile
      | .error e => throw (IO.userError e)
    catch e =>
      log .warn s!"fetching a tile failed: {e}" [("src", src)]
      throw e) yieldToEventLoop lo hi

end Inkproof.Web.Host
