/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Legend

namespace Inkproof.Web

namespace Highlight

/-- Validate the raw `highlight` attribute: a missing one or `off` highlights nothing, `on` highlights the item under the cursor. -/
def parse : Option String → Except String Bool
  | none | some "off" => .ok false
  | some s => if Legend.words s = ["on"] then .ok true
    else .error s!"attribute highlight is \"{s}\", expected on or off"

theorem parse_none : parse none = .ok false := rfl

theorem parse_off : parse (some "off") = .ok false := rfl

theorem parse_on : parse (some "on") = .ok true := by
  have : Legend.words "on" = ["on"] := by decide +kernel
  simp [parse, this]

end Highlight

end Inkproof.Web
