/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Host.Chart
import Inkproof.Scene.Axis

namespace Inkproof.Web.Host

open Inkproof.Scene Inkproof.Axis

private def ratToFloat (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

/-- A colour as CSS writes it. -/
def colorCss (c : Color) : String :=
  s!"rgba({c.r}, {c.g}, {c.b}, {showFloat (c.a.toFloat / 255)})"

theorem colorCss_eq (c : Color) : colorCss c = s!"rgba({c.r}, {c.g}, {c.b}, {showFloat (c.a.toFloat / 255)})" := rfl

/-- A text style as a Canvas 2D font. -/
def textFont (s : TextStyle) : String :=
  s!"{showFloat (ratToFloat s.size)}px {s.family}"

theorem textFont_eq (s : TextStyle) : textFont s = s!"{showFloat (ratToFloat s.size)}px {s.family}" := rfl

/-- The Canvas 2D label for `l` on the `side` axis of a plot, set in the font and colour of its style. A horizontal label is centred on the anchor, below a bottom axis and above a top one; a turned label ends at the anchor on a bottom axis and starts there on a top one, vertically centred, turned a quarter or an eighth of a turn anticlockwise; a label on a left axis ends at the anchor and one on a right axis starts there, vertically centred and unturned. -/
def Label.ofPlaced (side : Side) (l : PlacedLabel) : Label :=
  let base : Label :=
    { text := l.text, x := ratToFloat l.anchor.x, y := ratToFloat l.anchor.y, font := textFont l.style, color := colorCss l.style.color }
  match side, l.rotation with
  | .bottom, .horizontal => { base with align := .center, baseline := .top }
  | .top, .horizontal => { base with align := .center, baseline := .bottom }
  | .bottom, .diagonal => { base with align := .end, baseline := .middle, rotation := -0.7853981633974483 }
  | .bottom, .vertical => { base with align := .end, baseline := .middle, rotation := -1.5707963267948966 }
  | .top, .diagonal => { base with align := .start, baseline := .middle, rotation := -0.7853981633974483 }
  | .top, .vertical => { base with align := .start, baseline := .middle, rotation := -1.5707963267948966 }
  | .left, _ => { base with align := .end, baseline := .middle }
  | .right, _ => { base with align := .start, baseline := .middle }

/-- The labels of an axis drawing, for the Canvas 2D layer. -/
def Label.ofDrawing (side : Side) (d : AxisDrawing) : Array Label :=
  (d.labels.map (Label.ofPlaced side)).toArray

theorem Label.ofPlaced_text (side : Side) (l : PlacedLabel) : (Label.ofPlaced side l).text = l.text := by
  unfold Label.ofPlaced; split <;> rfl

theorem Label.ofPlaced_position (side : Side) (l : PlacedLabel) :
    (Label.ofPlaced side l).x = ratToFloat l.anchor.x ∧ (Label.ofPlaced side l).y = ratToFloat l.anchor.y := by
  unfold Label.ofPlaced; split <;> exact ⟨rfl, rfl⟩

theorem Label.ofPlaced_bottom_horizontal (t : String) (p : Pt) :
    let l := Label.ofPlaced .bottom { text := t, anchor := p, rotation := .horizontal }
    l.align = .center ∧ l.baseline = .top ∧ l.rotation = 0 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_bottom_diagonal (t : String) (p : Pt) :
    let l := Label.ofPlaced .bottom { text := t, anchor := p, rotation := .diagonal }
    l.align = .end ∧ l.baseline = .middle ∧ l.rotation = -0.7853981633974483 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_bottom_vertical (t : String) (p : Pt) :
    let l := Label.ofPlaced .bottom { text := t, anchor := p, rotation := .vertical }
    l.align = .end ∧ l.baseline = .middle ∧ l.rotation = -1.5707963267948966 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_left (t : String) (p : Pt) (r : Rotation) :
    let l := Label.ofPlaced .left { text := t, anchor := p, rotation := r }
    l.align = .end ∧ l.baseline = .middle ∧ l.rotation = 0 := by
  cases r <;> exact ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_top_horizontal (t : String) (p : Pt) :
    let l := Label.ofPlaced .top { text := t, anchor := p, rotation := .horizontal }
    l.align = .center ∧ l.baseline = .bottom ∧ l.rotation = 0 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_top_diagonal (t : String) (p : Pt) :
    let l := Label.ofPlaced .top { text := t, anchor := p, rotation := .diagonal }
    l.align = .start ∧ l.baseline = .middle ∧ l.rotation = -0.7853981633974483 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_top_vertical (t : String) (p : Pt) :
    let l := Label.ofPlaced .top { text := t, anchor := p, rotation := .vertical }
    l.align = .start ∧ l.baseline = .middle ∧ l.rotation = -1.5707963267948966 := ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_right (t : String) (p : Pt) (r : Rotation) :
    let l := Label.ofPlaced .right { text := t, anchor := p, rotation := r }
    l.align = .start ∧ l.baseline = .middle ∧ l.rotation = 0 := by
  cases r <;> exact ⟨rfl, rfl, rfl⟩

theorem Label.ofPlaced_style (side : Side) (l : PlacedLabel) :
    (Label.ofPlaced side l).font = textFont l.style ∧ (Label.ofPlaced side l).color = colorCss l.style.color := by
  unfold Label.ofPlaced; split <;> exact ⟨rfl, rfl⟩

theorem Label.ofDrawing_toList (side : Side) (d : AxisDrawing) :
    (Label.ofDrawing side d).toList = d.labels.map (Label.ofPlaced side) := by
  simp [Label.ofDrawing]

theorem Label.ofDrawing_size (side : Side) (d : AxisDrawing) :
    (Label.ofDrawing side d).size = d.labels.length := by
  simp [Label.ofDrawing]

end Inkproof.Web.Host
