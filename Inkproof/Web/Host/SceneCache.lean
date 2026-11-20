/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Host.Chart
import Inkproof.Web.SceneState

namespace Inkproof.Web.Host

open Inkproof.Gpu

/-- Buffer numbers a chart may use; every chart draws on one context, so each numbers its buffers from a range of its own. -/
private def bufferRange : Nat := 1048576

private initialize nextCache : IO.Ref Nat ← IO.mkRef 0

/-- One chart's buffers on the GPU, kept across frames and discarded when a lost context took them. -/
structure SceneCache where
  base : Nat
  state : IO.Ref (Option SceneState)

/-- A cache numbering its buffers from a range no other cache uses. -/
def SceneCache.new : IO SceneCache := do
  let n ← nextCache.modifyGet fun n => (n, n + 1)
  return { base := n * bufferRange, state := ← IO.mkRef none }

/-- Build a frame with `f`, which is given the cache of buffers already on the GPU and whether nothing has yet been drawn from it (a first frame, or the first after a lost context), and returns the cache it leaves and the frame. -/
def SceneCache.build {α : Type} (c : SceneCache) (f : Cache → Bool → IO (Cache × α)) : IO α := do
  let s := SceneState.current c.base (← contextGeneration) (← c.state.get)
  let (cache, result) ← f s.cache (!s.drawn)
  c.state.set (some (s.drew cache))
  return result

/-- Forget the buffers, as when the chart's data changed: the next frame builds from an empty cache. -/
def SceneCache.invalidate (c : SceneCache) : IO Unit := c.state.set none

end Inkproof.Web.Host
