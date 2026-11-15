/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Std.Data.HashMap

namespace Inkproof.Web

/-- Measured text sizes in CSS pixels, keyed by font and text, so that unchanged text is measured once. -/
structure TextCache where
  sizes : Std.HashMap (String × String) (Float × Float) := {}
  deriving Inhabited

namespace TextCache

def empty : TextCache := {}

/-- The remembered size of `text` in `font`, if it has been measured. -/
def find? (c : TextCache) (font text : String) : Option (Float × Float) :=
  c.sizes[(font, text)]?

def insert (c : TextCache) (font text : String) (size : Float × Float) : TextCache :=
  ⟨c.sizes.insert (font, text) size⟩

theorem find?_insert (c : TextCache) (font text : String) (size : Float × Float) :
    (c.insert font text size).find? font text = some size := by
  simp [find?, insert]

theorem find?_empty (font text : String) : empty.find? font text = none := by
  simp [find?, empty]

/-- The cached size, or the result of `measure` (which is then the only measurement taken). -/
def getOrMeasure {m : Type → Type} [Monad m] (c : TextCache) (font text : String)
    (measure : String → String → m (Float × Float)) : m ((Float × Float) × TextCache) := do
  match c.find? font text with
  | some size => return (size, c)
  | none =>
    let size ← measure font text
    return (size, c.insert font text size)

/-- A text already measured is not measured again. -/
theorem getOrMeasure_found {m : Type → Type} [Monad m] [LawfulMonad m] (c : TextCache) (font text : String)
    (measure : String → String → m (Float × Float)) {size : Float × Float} (h : c.find? font text = some size) :
    c.getOrMeasure font text measure = pure (size, c) := by
  simp [getOrMeasure, h]

/-- The measurement function Axis consumes. Text that was never measured is not a number, which Axis drops rather than places. -/
def measurer (c : TextCache) (font : String) (text : String) : Float × Float :=
  (c.find? font text).getD (0.0 / 0.0, 0.0 / 0.0)

theorem measurer_insert (c : TextCache) (font text : String) (size : Float × Float) :
    (c.insert font text size).measurer font text = size := by
  simp [measurer, find?_insert]

end TextCache

end Inkproof.Web
