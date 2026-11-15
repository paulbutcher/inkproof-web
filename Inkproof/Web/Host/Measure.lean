/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Lasm.JS.Web.Support
import Inkproof.Web.Text
import Inkproof.Web.Host.Console

namespace Inkproof.Web.Host
open Lasm.JS

initialize textCache : IO.Ref TextCache ← IO.mkRef TextCache.empty
initialize measuringContext : IO.Ref (Option Value) ← IO.mkRef none

private def context2d : IO (Option Value) := do
  if let some ctx ← measuringContext.get then return some ctx
  let canvas ← (← (← global).get "document").callMethod "createElement" #[toJS "canvas"]
  let ctx ← Web.Support.optionalValue (← canvas.callMethod "getContext" #[toJS "2d"] Data)
  if ctx.isNone then log .warn "text cannot be measured, no 2D context"
  measuringContext.set ctx
  return ctx

private def measureOnce (ctx : Value) (font text : String) : IO (Float × Float) := do
  ctx.set "font" font
  let m ← ctx.callMethod "measureText" #[toJS text]
  let width ← m.get "width" Float
  let ascent ← m.get "fontBoundingBoxAscent" Float
  let descent ← m.get "fontBoundingBoxDescent" Float
  return (width, ascent + descent)

/-- Measure each text in `font`, taking a measurement only for texts not measured before, and return the function Axis consumes. A text the browser could not measure is not a number to it. -/
def measurer (font : String) (texts : Array String) : IO (String → Float × Float) := do
  let some ctx ← context2d | return fun _ => (0.0 / 0.0, 0.0 / 0.0)
  let mut cache ← textCache.get
  for text in texts do
    (_, cache) ← cache.getOrMeasure font text (measureOnce ctx)
  textCache.set cache
  return cache.measurer font

end Inkproof.Web.Host
