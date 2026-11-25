/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
namespace Inkproof.Web

/-- A region of the plot the application drew, such as a bar, a box, a candle, an interval or an annotation, as a rectangle in data coordinates. -/
structure Item where
  x0 : Float
  x1 : Float
  y0 : Float
  y1 : Float
  /-- What the tooltip reads while the cursor is over it. -/
  description : Option String := none
  /-- The series it belongs to. -/
  series : Option Nat := none

namespace Item

/-- Whether `(x, y)` lies in the rectangle, edges included, whichever way round its corners are given. -/
def contains (i : Item) (x y : Float) : Bool :=
  min i.x0 i.x1 ≤ x && x ≤ max i.x0 i.x1 && min i.y0 i.y1 ≤ y && y ≤ max i.y0 i.y1

theorem contains_eq (i : Item) (x y : Float) :
    i.contains x y = (min i.x0 i.x1 ≤ x && x ≤ max i.x0 i.x1 && min i.y0 i.y1 ≤ y && y ≤ max i.y0 i.y1) := rfl

private def hitBelow (items : Array Item) (x y : Float) : Nat → Option Nat
  | 0 => none
  | n + 1 => if (items[n]?.map (·.contains x y)) = some true then some n else hitBelow items x y n

/-- The index of the topmost item containing `(x, y)`: later items lie over earlier ones. -/
def hit (items : Array Item) (x y : Float) : Option Nat := hitBelow items x y items.size

private theorem hitBelow_some (items : Array Item) (x y : Float) (n i : Nat) (h : hitBelow items x y n = some i) :
    i < n ∧ (items[i]?.map (·.contains x y)) = some true ∧
      ∀ j, i < j → j < n → (items[j]?.map (·.contains x y)) ≠ some true := by
  induction n generalizing i with
  | zero => simp [hitBelow] at h
  | succ n ih =>
    simp only [hitBelow] at h
    split at h
    · cases h; refine ⟨Nat.lt_succ_self _, ‹_›, fun j hj hn => by omega⟩
    · obtain ⟨a, b, c⟩ := ih i h
      refine ⟨by omega, b, fun j hj hn => ?_⟩
      if e : j = n then subst e; assumption else exact c j hj (by omega)

private theorem hitBelow_none (items : Array Item) (x y : Float) (n : Nat) (h : hitBelow items x y n = none) :
    ∀ j, j < n → (items[j]?.map (·.contains x y)) ≠ some true := by
  induction n with
  | zero => intro j hj; omega
  | succ n ih =>
    simp only [hitBelow] at h
    split at h
    · simp at h
    · intro j hj
      if e : j = n then subst e; assumption else exact ih h j (by omega)

/-- The item `hit` returns contains the point, and no later item does. -/
theorem hit_some (items : Array Item) (x y : Float) (i : Nat) (h : hit items x y = some i) :
    ∃ it, items[i]? = some it ∧ it.contains x y = true ∧
      ∀ j it', i < j → items[j]? = some it' → it'.contains x y = false := by
  obtain ⟨_, b, c⟩ := hitBelow_some items x y _ i h
  cases hi : items[i]? with
  | none => simp [hi] at b
  | some it =>
    refine ⟨it, rfl, by simpa [hi] using b, fun j it' hij hj => ?_⟩
    have hjs : j < items.size := (Array.getElem?_eq_some_iff.1 hj).1
    have := c j hij hjs
    simpa [hj] using this

/-- No item is returned only when none contains the point. -/
theorem hit_none (items : Array Item) (x y : Float) (h : hit items x y = none) :
    ∀ it ∈ items, it.contains x y = false := by
  intro it hit'
  obtain ⟨j, hj, rfl⟩ := Array.getElem_of_mem hit'
  have := hitBelow_none items x y _ h j hj
  simpa [Array.getElem?_eq_getElem hj] using this

/-- The rectangle `(left, top, width, height)`, on screen, of a data rectangle whose corners map to `(sx0, sy0)` and `(sx1, sy1)`, cut to the plot of `width` by `height`. -/
def screenRect (sx0 sy0 sx1 sy1 width height : Float) : Float × Float × Float × Float :=
  let l := max 0 (min sx0 sx1)
  let t := max 0 (min sy0 sy1)
  let r := min width (max sx0 sx1)
  let b := min height (max sy0 sy1)
  (l, t, max 0 (r - l), max 0 (b - t))

theorem screenRect_eq (sx0 sy0 sx1 sy1 width height : Float) :
    screenRect sx0 sy0 sx1 sy1 width height =
      (max 0 (min sx0 sx1), max 0 (min sy0 sy1),
       max 0 (min width (max sx0 sx1) - max 0 (min sx0 sx1)),
       max 0 (min height (max sy0 sy1) - max 0 (min sy0 sy1))) := rfl

end Item

end Inkproof.Web
