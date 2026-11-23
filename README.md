# Inkproof.Web

The browser host of Inkproof: a custom element that draws a chart on a shared WebGL2 context with a Canvas 2D text layer, written in Lean under Lasm with no hand-written JavaScript beyond a minimal shim. Part of Inkproof. Released under the Apache 2.0 license; see `LICENSE`.

## Requiring it

```lean
require «inkproof-web» from git "https://github.com/paulbutcher/inkproof-web" @ "v0.4.8"
```

Modules that import Lasm (`Inkproof.Web.Host.*`) build only under Lasm's browser target; the rest build natively. See `DESIGN.md`.

## What it does

- Draw an Inkproof chart in a web page as a custom element, run on one WebGL2 context shared by every chart, recovered after a lost context: `Inkproof.Web.Host.register`.
- Keep buffers and programs on the GPU between draws so a list can draw what an earlier one uploaded, and learn when a lost context discarded them: `Host.contextGeneration`, the `inkproof-contextrestored` event.
- Keep a chart's buffers on the GPU across frames without page bookkeeping: `Host.SceneCache.new` numbers the chart's buffers apart from other charts', `SceneCache.build` hands your frame builder the cache and whether it is the first since a lost context (which it empties itself), and `SceneCache.invalidate` forgets it when the data changes; the pure state is `SceneState`.
- Redraw only when something changed, never while idle: `Frame`, `Frame.invalidate`, `Frame.shouldDraw`.
- Size the drawing surface to the device pixel ratio: `Size`, `backingPx`.
- Draw text over a chart, anchored and aligned on a point and turned about it, as axis labels need: `Host.Label` with `align`, `baseline` and `rotation`.
- Turn the labels Scene places for an axis into Canvas 2D labels, aligned and turned as each side of the plot needs: `Host.Label.ofPlaced`, `Host.Label.ofDrawing`.
- Measure text once per font and string: `TextCache`.
- Read and validate the element's attributes, reporting bad ones instead of defaulting them: `ChartAttrs.parse`.
- Log to the browser console at a threshold, warn by default: `Level`, `Level.parse?`, `Level.enabled`.
- Control a chart from the keyboard (zoom, pan, cursor, series): `Command.ofKey`, `Nav`, `Nav.apply`, `NavConfig`.
- Give a chart a new scene without losing its zoom, cursor or series, and apply a command such as reset from the page: `Host.setScene`, `Host.apply`.
- Zoom, pan and box-zoom a chart with the wheel, a drag, shift-drag or a two-finger pinch, and learn the data position under the pointer from the `inkproof-pointer` event: `Nav.input`, with the conversions from Viewport's `Gesture`; a plot inset in the element, for axis labels beside it, is placed by `Access.plotOrigin`.
- Choose which axes a shift-drag box zooms (x, y, both or the dominant direction of the drag) and the least drag that counts, by the `box-zoom` and `box-min` attributes: `BoxConfig`, `BoxConfig.input`, `BoxConfig.parse`; with `drag="box"` a plain drag draws the box and shift-drag pans: `DragMode`.
- Link chart elements so that zooming, panning or box-zooming one moves the x range of the others, with only a `group` attribute naming the group: `Group.parse`.
- Draw a cursor line at the data position under the pointer, vertical, horizontal or both, shown on the other charts of the group too, or set from the page: the `cursor` attribute, `CursorMode`, `Cursor.lines`, `Host.setCursor`.
- Let a drag select an x range that other charts in the group show, as a range selector: the `select` attribute, `inkproof-select`, `SelectMode`, `Select.config`, `Select.shown`, `Host.setSelection`.
- Make a responsive chart's scene again for its size, given the canvas's CSS size and called again when it changes: `Host.registerSized`.
- Make a chart's scene in device pixels, such as a Gpu frame whose clips and stroke widths must match the canvas at any device pixel ratio, given the CSS and the backing store sizes: `Host.registerPixels`.
- Show a tooltip at the data point nearest the pointer, by x or in the plane, and a legend of the series with their value at the cursor's x (their last value when it is away), a readout of the cursor's position and a click to hide or show each, and draw the cursor lines dotted with `cursor-dotted`, with the text readable from the page: the `tooltip` and `legend` attributes (the `tooltip` attribute is a list of words: `x` or `xy`, the metric by which the nearest point is found; `shared`, which lists every series at the cursor's x instead; `no-x-value`; `point` or `pointer`, what it is placed against; `top-right`, `top-left`, `bottom-right` or `bottom-left`, the way it opens, flipping and moving to stay inside the chart; and a number, the offset in pixels, 8 by default, with `Tooltip.parse`, `Tooltip.Style`, `Tooltip.Style.place`, `Tooltip.single`, `Tooltip.sharedText`, and its look set from the page with the custom properties `--inkproof-tooltip-color`, `-background`, `-border-color`, `-border-width`, `-border-radius`, `-font-family`, `-font-size`, `-padding` and `-shadow`, or `::part(tooltip)`; the `legend` attribute is a list of words: a placement, `top-left`, `top-right`, `bottom-left` or `bottom-right` over the plot, or `below-left`, `below-center` or `below-right` (`bottom`) in room of its own below it; a layout, `vertical` or `horizontal`, wrapping when a row is too wide; `static`, which lists only each series' colour and name, for charts whose series have no value at an x; and `x`, `y`, `no-x`, `no-y` to show or hide each cursor position, shown with values and hidden without; `Legend.parseStyle`, `Legend.Style`), `Access.traces`, `Nearest.find`, `Access.groups` (groups of named values per x, such as a candle's open, high, low and close, shown in the legend at the nearest x or the last, and toggled by a click, with an `inkproof-group` event, only when the group is `hideable`; `ValueGroup.words` gives text such as a state in place of numbers), `Legend.rows`, `Legend.groupRows`, `Legend.readout`, `Legend.toggle`, the `inkproof-series` event.
- Reset a chart, or take it out of its group and put it back, from a button with no page script: `<button data-reset="id">` and `<button data-unlink="id" data-group="name">`, enabled by `Host.register ... (buttons := true)`; `Group.toggled` is the pure rule.
- Read the payloads of the events a chart dispatches: `Host.viewOf` for `inkproof-view` (a `View Float`, by `View.ofBounds`) and `Host.pointerOf` for `inkproof-pointer`.
- Describe a chart for assistive technology, with a name, a summary, a cursor reading and a data table: `Access`, `Access.summaryText`, `Access.cursorText`.
- Format numbers and lines of text for those descriptions: `showFloat`, `formatLine`, `describe`.
- Fetch a tile, or a byte range of a file, with the status checked and a failure logged: `Host.fetchTile`.
- Aggregate a range of nodes over tiles fetched one at a time without blocking the page: `Host.queryTiles`.
- Share decoded tiles, and in-flight fetches, between concurrent queries, bounded and least recently used first: `Host.TileCache.new`, passed to `queryTiles`, `queryColumns` and `queryColumnsFrom`.
- Aggregate each of a chart's pixel columns over a tiled pyramid, fetching each tile once: `Host.queryColumns`.
- The same for a pyramid stored only from level `k0` up, reading the finest zooms from raw files by byte range: `Host.queryColumnsFrom`.
