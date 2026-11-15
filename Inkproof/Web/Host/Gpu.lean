/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS

namespace Inkproof.Web.Host
open Lasm.JS

/-- A fresh interpreter state (its buffer, program and uniform tables). -/
@[js "inkproof-gpu-js" "newState"] opaque newState : IO Value

/-- Interpret an encoded command list on a WebGL2 context. -/
@[js "inkproof-gpu-js" "run"] opaque run : Value → Value → ByteArray → IO Unit

end Inkproof.Web.Host
