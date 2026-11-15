/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS
import Inkproof.Web.Log

namespace Inkproof.Web.Host
open Lasm.JS

initialize threshold : IO.Ref Level ← IO.mkRef Level.defaultThreshold

/-- Set the console threshold; messages below it are dropped. -/
def setThreshold (l : Level) : IO Unit := threshold.set l

/-- The only route to the console. `values` are the facts that decided what was logged. -/
def log (l : Level) (message : String) (values : List (String × String) := []) : IO Unit := do
  if l.enabled (← threshold.get) then
    let console ← (← global).get "console"
    console.callMethod l.name #[toJS (formatLine l message values)] Unit

end Inkproof.Web.Host
