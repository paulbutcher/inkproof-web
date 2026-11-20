/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Viewport.View

namespace Inkproof.Web

open Inkproof.Viewport

namespace View

/-- The view an `inkproof-view` event describes, from the bounds its detail carries: each axis starts at the start bound and spans to the end bound. -/
def ofBounds (xStart xEnd yStart yEnd : Float) : View Float := ⟨⟨xStart, xEnd - xStart⟩, ⟨yStart, yEnd - yStart⟩⟩

theorem ofBounds_x (xStart xEnd yStart yEnd : Float) :
    (ofBounds xStart xEnd yStart yEnd).x = ⟨xStart, xEnd - xStart⟩ := rfl

theorem ofBounds_y (xStart xEnd yStart yEnd : Float) :
    (ofBounds xStart xEnd yStart yEnd).y = ⟨yStart, yEnd - yStart⟩ := rfl

end View

namespace Group

/-- The `group` attribute a chart has after a button toggles its membership: none if it was in a group, else the group the button names. -/
def toggled (current named : Option String) : Option String :=
  match current with
  | some _ => none
  | none => named

theorem toggled_linked (name : String) (named : Option String) : toggled (some name) named = none := rfl

theorem toggled_unlinked (named : Option String) : toggled none named = named := rfl

end Group

end Inkproof.Web
