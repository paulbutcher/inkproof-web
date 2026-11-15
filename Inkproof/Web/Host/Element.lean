/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lasm.JS

namespace Inkproof.Web.Host
open Lasm.JS

/-- Define a custom element whose lifecycle callbacks call the given functions with the element. Classes extending `HTMLElement` cannot be written in Lean, so this is the one binding with a shim (shim/inkproof-web-element). -/
@[js "inkproof-web-element" "define"]
opaque defineElement : String → Array String → Value → Value → Value → IO Unit

end Inkproof.Web.Host
