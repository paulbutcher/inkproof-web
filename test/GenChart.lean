/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Inkproof.Gpu

open Inkproof.Gpu

/-- The command list the browser tests draw: lift any scissor and clear to an opaque orange, then a blue triangle over the left half of the lower left, clipped by a scissor to the leftmost 100 device pixels of a 400 by 200 canvas. -/
def chart : List Cmd :=
  let one : UInt32 := 0x3f800000
  let minusOne : UInt32 := 0xbf800000
  [⟨8, [.words []]⟩, ⟨6, [.u32 0xff8000ff]⟩, ⟨7, [.u32 0]⟩, ⟨0, [.u32 0]⟩,
   ⟨1, [.u32 0, .words [minusOne, minusOne, 0, minusOne, minusOne, one]]⟩,
   ⟨3, [.u32 0]⟩, ⟨4, [.u32 0, .words [one, one]]⟩, ⟨4, [.u32 1, .words [0, 0]]⟩,
   ⟨4, [.u32 2, .words [0, 0, one, one]]⟩, ⟨8, [.words [0, 0, 100, 200]]⟩, ⟨5, [.u32 0, .u32 3]⟩]

/-- The same picture drawn by a list that uploads nothing: it only selects the program and buffer an earlier list made. -/
def reuse : List Cmd :=
  let one : UInt32 := 0x3f800000
  [⟨8, [.words []]⟩, ⟨6, [.u32 0xff8000ff]⟩, ⟨3, [.u32 0]⟩, ⟨4, [.u32 0, .words [one, one]]⟩, ⟨4, [.u32 1, .words [0, 0]]⟩,
   ⟨4, [.u32 2, .words [0, 0, one, one]]⟩, ⟨8, [.words [0, 0, 100, 200]]⟩, ⟨5, [.u32 0, .u32 3]⟩]

def main (args : List String) : IO UInt32 := do
  match args with
  | [path] =>
    if let some dir := (System.FilePath.mk path).parent then IO.FS.createDirAll dir
    IO.FS.writeBinFile path (ByteArray.mk (encode chart).toArray)
    IO.FS.writeBinFile ((System.FilePath.mk path).withFileName "reuse.bin") (ByteArray.mk (encode reuse).toArray)
    return 0
  | _ =>
    IO.eprintln "usage: genchart <chart output file>"
    return 1
