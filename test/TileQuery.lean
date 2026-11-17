/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Host.Tiles

open Lasm.JS Inkproof.Core Inkproof.Web.Host

/-- Each byte of a tile is one node of a sum, and a tile holds four. -/
def decode (body : ByteArray) : Except String (Array (Total Nat)) :=
  if body.size == 4 then .ok (body.toList.toArray.map fun b => ⟨b.toNat⟩)
  else .error s!"a tile of {body.size} bytes"

/-- Sums nodes `lo` to `hi - 1` of the tiles under `tiles/`, four nodes to a tile, and publishes the result, or the failure, on the body. -/
def main : IO Unit := do
  let body ← (← (← global).get "document").get "body" Value
  discard <| Std.Async.Async.toIO (do
    for (lo, hi, name) in [(2, 14, "sum"), (2, 18, "missing")] do
      try
        let total ← queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin") decode lo hi
        body.callMethod "setAttribute" #[toJS name, toJS (toString total.get)] Unit
      catch e =>
        body.callMethod "setAttribute" #[toJS name, toJS s!"error: {e}"] Unit
    try
      let cols ← queryColumns (M := Total Nat) 4 (by decide) 2 1 (fun _ t => s!"tiles/{t}.bin") decode 2 14 4
      body.callMethod "setAttribute" #[toJS "columns", toJS (toString (cols.map (·.get)))] Unit
    catch e =>
      body.callMethod "setAttribute" #[toJS "columns", toJS s!"error: {e}"] Unit
    try
      let whole ← fetchTile "tiles/1.bin"
      let part ← fetchTile "tiles/1.bin" (some (1, 2))
      body.callMethod "setAttribute" #[toJS "range", toJS (toString (part == whole.extract 1 3))] Unit
    catch e =>
      body.callMethod "setAttribute" #[toJS "range", toJS s!"error: {e}"] Unit
    body.callMethod "setAttribute" #[toJS "done", toJS "true"] Unit : Async Unit)
