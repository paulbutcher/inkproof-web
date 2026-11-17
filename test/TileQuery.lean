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
      let source := fun (lo hi : Nat) => (Array.range 4).filterMap fun t =>
        if lo < 4 * t + 4 ∧ 4 * t < hi then some { url := s!"tiles/{t}.bin", first := 4 * t, start := 0, len := 4 : RawRange }
        else none
      let cols ← queryColumnsFrom (M := Total Nat) 4 (by decide) 2 3 2 (fun _ t => s!"tiles/{t}.bin") decode source decode 10 20 3
      body.callMethod "setAttribute" #[toJS "raw", toJS (toString (cols.map (·.get)))] Unit
    catch e =>
      body.callMethod "setAttribute" #[toJS "raw", toJS s!"error: {e}"] Unit
    try
      let whole ← fetchTile "tiles/1.bin"
      let part ← fetchTile "tiles/1.bin" (some (1, 2))
      body.callMethod "setAttribute" #[toJS "range", toJS (toString (part == whole.extract 1 3))] Unit
    catch e =>
      body.callMethod "setAttribute" #[toJS "range", toJS s!"error: {e}"] Unit
    try
      let cache : TileCache (Total Nat) ← TileCache.new 8
      let url := fun (_ t : Nat) => s!"tiles/{t}.bin?cached"
      let a ← queryTiles (M := Total Nat) 4 (by decide) (url 0) decode 2 14 (some cache)
      let cols ← queryColumns (M := Total Nat) 4 (by decide) 2 1 url decode 2 14 4 (some cache)
      let b ← queryTiles (M := Total Nat) 4 (by decide) (url 0) decode 2 14 (some cache)
      body.callMethod "setAttribute" #[toJS "cached", toJS s!"{a.get} {cols.map (·.get)} {b.get}"] Unit
    catch e =>
      body.callMethod "setAttribute" #[toJS "cached", toJS s!"error: {e}"] Unit
    let small : TileCache (Total Nat) ← TileCache.new 1
    for _ in [0:2] do
      discard <| queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin?small") decode 4 12 (some small)
    let bad : TileCache (Total Nat) ← TileCache.new 4
    for _ in [0:2] do
      try
        discard <| queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin?bad") decode 16 20 (some bad)
      catch _ =>
        pure ()
    let shared : TileCache (Total Nat) ← TileCache.new 8
    let racers ← Std.Async.Async.concurrentlyAll <| (Array.range 6).map fun _ =>
      queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin?shared") decode 2 14 (some shared)
    body.callMethod "setAttribute" #[toJS "shared", toJS s!"{racers.map (·.get)}"] Unit
    let now : Async Float := do (← (← global).get "performance").callMethod "now" #[] Float
    let timed := fun (name : String) (act : Async Unit) => do
      let t0 ← now
      act
      body.callMethod "setAttribute" #[toJS name, toJS (toString ((← now) - t0))] Unit
    let warm : TileCache (Total Nat) ← TileCache.new 8
    let warmUrl := fun (t : Nat) => s!"tiles/{t}.bin?timed"
    discard <| queryTiles (M := Total Nat) 4 (by decide) warmUrl decode 0 16 (some warm)
    timed "tUncached" <| discard <| queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin?timed2") decode 0 16
    timed "tCached" <| discard <| queryTiles (M := Total Nat) 4 (by decide) warmUrl decode 0 16 (some warm)
    let many : TileCache (Total Nat) ← TileCache.new 512
    timed "tMany" <| discard <| Std.Async.Async.concurrentlyAll <| (Array.range 8).map fun _ => do
      for st in [0:30] do
        discard <| queryTiles (M := Total Nat) 4 (by decide) (fun t => s!"tiles/{t}.bin?many{st}") decode 0 16 (some many)
    body.callMethod "setAttribute" #[toJS "done", toJS "true"] Unit : Async Unit)
