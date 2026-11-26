/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Host.SceneCache
import Inkproof.Web.Pixels
import Inkproof.Web.Series

namespace Inkproof.Web.Host

open Lasm.JS Inkproof.Gpu

/-- Decode an `inkproof-series` event; none, logged, if its detail is not a series and a flag. -/
def decodeSeriesEvent (event : Value) : IO (Option SeriesEvent) := do
  let detail ← event.get "detail" Value
  let decoded ← try
      pure (SeriesEvent.decode (← detail.get "series" Float) (← detail.get "hidden" Bool))
    catch e =>
      log .warn "inkproof-series event with an unreadable detail" [("error", toString e)]
      pure none
  if decoded.isNone then log .warn "inkproof-series event names no series" []
  return decoded

/-- Like `registerPixels`, for a loader that makes its scene from the canvas's sizes and theme as one `Pixels`. -/
def registerCanvas (tag : String) (build : String → Pixels → IO Scene) (buttons : Bool := false) : IO Unit :=
  registerThemed tag (fun src css backing theme => build src ⟨css, backing, theme⟩) buttons

/-- Like `registerCanvas`, for a chart whose axes carry the titles the element's attributes give. -/
def registerCanvasTitled (tag : String) (build : String → Pixels → AxisTitles → IO Scene) (buttons : Bool := false) : IO Unit :=
  registerTitled tag (fun src css backing theme titles => build src ⟨css, backing, theme⟩ titles) buttons

/-- A chart's buffers on the GPU and the draws recorded for the layers in them, kept across frames. -/
structure Retention where
  cache : SceneCache

/-- A retention numbering its buffers apart from every other chart's. -/
def Retention.new : IO Retention := do pure { cache := ← SceneCache.new }

/-- Forget the buffers, as when the chart's data changed. -/
def Retention.invalidate (r : Retention) : IO Unit := r.cache.invalidate

/-- Build a frame with `f`, given what the chart holds, and keep what `f` leaves. -/
def Retention.build {α : Type} (r : Retention) (f : Retained → Bool → IO (Retained × α)) : IO α :=
  r.cache.buildRetained f

/-- Define the element `tag`, and draw each chart `build` makes of its `src` for its canvas's size and the series its legend has hidden. A click on a legend entry hides or shows a series by calling what `build` returned again, and only a change of size calls `build` again. `build` is given the chart's `Retention`, kept for the page's life per `src`. -/
def registerRetainedAs (tag : String) (build : String → Pixels → Retention → IO (Array Bool → IO Scene)) : IO Unit := do
  let hidden ← IO.mkRef (({} : Std.HashMap String Hidden))
  let draws ← IO.mkRef (({} : Std.HashMap String ((Array Bool → IO Scene) × Nat)))
  let caches ← IO.mkRef (({} : Std.HashMap String Retention))
  registerCanvas tag fun src px => do
    let cache ← match (← caches.get).get? src with
      | some c => pure c
      | none => do let c ← Retention.new; caches.modify (·.insert src c); pure c
    let draw ← build src px cache
    let scene ← draw ((← hidden.get).getD src #[])
    draws.modify (·.insert src (draw, scene.access.traces.size))
    return scene
  let toggled ← Function.ofSyncFn fun args => do
    if let some (Data.ref event _) := args[0]? then
      if let some e ← decodeSeriesEvent event then
        let el ← event.get "target" Value
        let src ← el.callMethod "getAttribute" #[toJS "src"] String
        if let some (draw, count) := (← draws.get).get? src then
          let off := Hidden.apply count ((← hidden.get).getD src #[]) e
          hidden.modify (·.insert src off)
          setScene el (← draw off)
    return .undefined
  (← (← global).get "document").callMethod "addEventListener" #[toJS "inkproof-series", toJS toggled] Unit

end Inkproof.Web.Host
