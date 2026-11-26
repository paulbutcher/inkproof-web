/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Web.Host.Chart
import Inkproof.Scene.Axis

namespace Inkproof.Web.Host

open Inkproof.Scene Inkproof.Axis

private def ratToFloat (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

/-- A text style as a Canvas 2D font. -/
def textFont (s : TextStyle) : String :=
  s!"{showFloat (ratToFloat s.size)}px {s.family}"

theorem textFont_eq (s : TextStyle) : textFont s = s!"{showFloat (ratToFloat s.size)}px {s.family}" := rfl

/-- The Canvas 2D label for `l` on the `side` axis of a plot, set in the font and colour of its style. A horizontal label is centred on the anchor, below a bottom axis and above a top one; a turned label ends at the anchor on a bottom axis and starts there on a top one, vertically centred, turned a quarter or an eighth of a turn anticlockwise; a label on a left axis ends at the anchor and one on a right axis starts there, vertically centred and unturned. -/
def Label.ofPlaced (side : Side) (l : PlacedLabel) : Label :=
  let base : Label :=
    { text := l.text, x := ratToFloat l.anchor.x, y := ratToFloat l.anchor.y, font := textFont l.style, color := colorCss l.style.color, second := l.context }
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

theorem Label.ofPlaced_second (side : Side) (l : PlacedLabel) : (Label.ofPlaced side l).second = l.context := by
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


/-- The Canvas 2D label for an axis title `l` placed by Scene on the `side` axis: centred on its anchor along the axis and extending away from the plot, turned to read upward on a left axis and downward on a right one. -/
def Label.ofTitle (side : Side) (l : PlacedLabel) : Label :=
  let base : Label :=
    { text := l.text, x := ratToFloat l.anchor.x, y := ratToFloat l.anchor.y, font := textFont l.style, color := colorCss l.style.color, align := .center, baseline := .bottom }
  match side with
  | .bottom => { base with baseline := .top }
  | .top => base
  | .left => { base with rotation := -1.5707963267948966 }
  | .right => { base with rotation := 1.5707963267948966 }

theorem Label.ofTitle_text (side : Side) (l : PlacedLabel) : (Label.ofTitle side l).text = l.text := by
  unfold Label.ofTitle; split <;> rfl

theorem Label.ofTitle_position (side : Side) (l : PlacedLabel) :
    (Label.ofTitle side l).x = ratToFloat l.anchor.x ∧ (Label.ofTitle side l).y = ratToFloat l.anchor.y := by
  unfold Label.ofTitle; split <;> exact ⟨rfl, rfl⟩

theorem Label.ofTitle_style (side : Side) (l : PlacedLabel) :
    (Label.ofTitle side l).font = textFont l.style ∧ (Label.ofTitle side l).color = colorCss l.style.color := by
  unfold Label.ofTitle; split <;> exact ⟨rfl, rfl⟩

theorem Label.ofTitle_bottom (l : PlacedLabel) :
    let t := Label.ofTitle .bottom l
    t.align = .center ∧ t.baseline = .top ∧ t.rotation = 0 := ⟨rfl, rfl, rfl⟩

theorem Label.ofTitle_top (l : PlacedLabel) :
    let t := Label.ofTitle .top l
    t.align = .center ∧ t.baseline = .bottom ∧ t.rotation = 0 := ⟨rfl, rfl, rfl⟩

theorem Label.ofTitle_left (l : PlacedLabel) :
    let t := Label.ofTitle .left l
    t.align = .center ∧ t.baseline = .bottom ∧ t.rotation = -1.5707963267948966 := ⟨rfl, rfl, rfl⟩

theorem Label.ofTitle_right (l : PlacedLabel) :
    let t := Label.ofTitle .right l
    t.align = .center ∧ t.baseline = .bottom ∧ t.rotation = 1.5707963267948966 := ⟨rfl, rfl, rfl⟩

/-- The gap, in CSS pixels, between the far end of an axis's tick labels and its title. -/
def axisTitleGap : Float := 8

/-- A whole number of quarter pixels no smaller than `x`, or zero for a negative or non-finite `x`. -/
private def quarterCeil (x : Float) : Rat :=
  if x.isFinite && 0 ≤ x then (Rat.ofInt (Int.ofNat (x * 4).ceil.toUInt64.toNat)) / 4 else 0

/-- How far past the plot's edge the label `l` of the `side` axis of the plot `r` reaches, given the measured `(width, height)` of its text: its anchor's distance from the edge and the extent of the text away from it, a second line counting one more line height. -/
def PlacedLabel.reach (side : Side) (r : Rect) (measure : String → String → Float × Float) (l : PlacedLabel) : Float :=
  let (w, h) := measure (textFont l.style) l.text
  let h := if l.context.isSome then 2 * h else h
  let size :=
    match side.horizontal, l.rotation with
    | true, .horizontal => h
    | true, .vertical => w
    | true, .diagonal => (w + h) * 0.7071067811865476
    | false, _ => w
  (ratToFloat (side.across l.anchor) - ratToFloat (side.edge r)) * ratToFloat side.outward + size

theorem PlacedLabel.reach_vertical (side : Side) (r : Rect) (measure : String → String → Float × Float) (l : PlacedLabel)
    (h : side.horizontal = false) :
    PlacedLabel.reach side r measure l =
      (ratToFloat (side.across l.anchor) - ratToFloat (side.edge r)) * ratToFloat side.outward
        + (measure (textFont l.style) l.text).1 := by
  unfold PlacedLabel.reach
  simp [h]

theorem PlacedLabel.reach_horizontal (side : Side) (r : Rect) (measure : String → String → Float × Float) (l : PlacedLabel)
    (h : side.horizontal = true) (rot : l.rotation = .horizontal) :
    PlacedLabel.reach side r measure l =
      (ratToFloat (side.across l.anchor) - ratToFloat (side.edge r)) * ratToFloat side.outward
        + (if l.context.isSome then 2 * (measure (textFont l.style) l.text).2 else (measure (textFont l.style) l.text).2) := by
  unfold PlacedLabel.reach
  simp [h, rot]

theorem PlacedLabel.reach_horizontal_vertical (side : Side) (r : Rect) (measure : String → String → Float × Float) (l : PlacedLabel)
    (h : side.horizontal = true) (rot : l.rotation = .vertical) :
    PlacedLabel.reach side r measure l =
      (ratToFloat (side.across l.anchor) - ratToFloat (side.edge r)) * ratToFloat side.outward
        + (measure (textFont l.style) l.text).1 := by
  unfold PlacedLabel.reach
  simp [h, rot]

theorem PlacedLabel.reach_diagonal (side : Side) (r : Rect) (measure : String → String → Float × Float) (l : PlacedLabel)
    (h : side.horizontal = true) (rot : l.rotation = .diagonal) :
    PlacedLabel.reach side r measure l =
      (ratToFloat (side.across l.anchor) - ratToFloat (side.edge r)) * ratToFloat side.outward
        + ((measure (textFont l.style) l.text).1
          + (if l.context.isSome then 2 * (measure (textFont l.style) l.text).2 else (measure (textFont l.style) l.text).2))
          * 0.7071067811865476 := by
  unfold PlacedLabel.reach
  simp [h, rot]

/-- The title of an axis and how far it reaches past the plot's edge. -/
structure AxisTitle where
  label : Label
  margin : Float

/-- The title `text` of the `side` axis of the plot `r` whose tick labels are `labels`: `axisTitleGap` beyond the widest of them, centred along the plot's edge, in `style` or else the colour of the axis's tick labels. `margin` is the room the plot must leave beyond its edge for the labels, the gap and the title; the labels' own reach does not depend on where the plot lies, so it can be had from a trial layout. -/
def axisTitle (side : Side) (r : Rect) (st : AxisStyle) (labels : List PlacedLabel) (text : String)
    (measure : String → String → Float × Float) (style : Option TextStyle := none) : AxisTitle :=
  let style := style.getD { TextStyle.axisTitle with color := st.labelText.color }
  let reach := labels.foldl (fun m l => let x := PlacedLabel.reach side r measure l; if x.isFinite && m < x then x else m) 0
  let height := (measure (textFont style) text).2
  { label := Label.ofTitle side (placeAxisTitle side r (quarterCeil reach) (quarterCeil axisTitleGap) text style)
    margin := reach + axisTitleGap + (if height.isFinite then height else ratToFloat style.size) }

theorem axisTitle_label (side : Side) (r : Rect) (st : AxisStyle) (labels : List PlacedLabel) (text : String)
    (measure : String → String → Float × Float) (style : Option TextStyle) :
    (axisTitle side r st labels text measure style).label.text = text :=
  Label.ofTitle_text _ _

theorem axisTitle_margin (side : Side) (r : Rect) (st : AxisStyle) (labels : List PlacedLabel) (text : String)
    (measure : String → String → Float × Float) (style : Option TextStyle) :
    (axisTitle side r st labels text measure style).margin =
      labels.foldl (fun m l => let x := PlacedLabel.reach side r measure l; if x.isFinite && m < x then x else m) 0
        + axisTitleGap
        + (let st := style.getD { TextStyle.axisTitle with color := st.labelText.color }
           let height := (measure (textFont st) text).2
           if height.isFinite then height else ratToFloat st.size) := rfl

/-- Measure the labels and the title text, and place the title of the `side` axis of `r`: see `axisTitle`. -/
def axisTitleMeasured (side : Side) (r : Rect) (st : AxisStyle) (d : AxisDrawing) (text : String)
    (style : Option TextStyle := none) : IO AxisTitle := do
  let titleFont := textFont (style.getD TextStyle.axisTitle)
  let mut seen : Array String := #[]
  for l in d.labels do
    let font := textFont l.style
    unless seen.contains font do
      seen := seen.push font
      discard <| measurer font ((d.labels.filter (textFont ·.style == font)).flatMap (fun l => [l.text]) |>.toArray)
  discard <| measurer titleFont #[text]
  let cache ← textCache.get
  return axisTitle side r st d.labels text cache.measurer style


end Inkproof.Web.Host
