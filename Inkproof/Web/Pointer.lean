/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Access

namespace Inkproof.Web

open Inkproof.Viewport

namespace Nav

/-- The state after a view input, which is how a pointer gesture reaches the view. -/
def input (c : NavConfig) (n : Nav) (i : Input Float) : Nav := { n with view := View.step c.view n.view i }

theorem input_eq (c : NavConfig) (n : Nav) (i : Input Float) :
    n.input c i = { n with view := View.step c.view n.view i } := rfl

theorem input_key (c : NavConfig) (n : Nav) (k : Key) : n.input c (.key k) = n.apply c (.view k) := rfl

end Nav

end Inkproof.Web
