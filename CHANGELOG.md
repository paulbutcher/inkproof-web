# Changelog

## [0.17.0]

- `legend="static"` (or `static bottom`) lists each series' colour and name with no values or readout, and still hides or shows a series on a click.

## [0.16.0]

- `legend="bottom"` puts the legend below the plot, outside it.
- `Host.registerSized` gives the loader the chart's CSS size and calls it again once the size settles after a resize.

## [0.15.1]

- The generated interpreter comes from Gpu v0.13.0, so a gradient fill or stroke is drawn blended between its stops.

## [0.15.0]

- A legend row shows its series' last value, marked "(last)", when the cursor is away.
- The legend starts with a readout of the cursor's position.
- The `cursor-dotted` attribute draws the cursor lines dotted.

## [0.14.1]

- A pointer press on a legend entry no longer reaches the chart's pointer capture, so a real click hides or shows its series.

## [0.14.0]

- The `tooltip` attribute shows the series and values of the visible point nearest the pointer, and the `legend` attribute lists the series with their value at the cursor's x and a click to hide or show each, reported as `inkproof-series`; `Nearest.find` (proved least), `Legend.rows`, `Legend.toggle`, `Trace` and `Access.traces` are the pure parts.

## [0.13.0]

- `SceneState` and `SceneCache` keep a chart's GPU cache across frames, discard it when the context is lost, number buffers per chart, and let a page invalidate it when its data changes.
- The `buttons` option of `Host.register` wires `data-reset` and `data-unlink` buttons with no page script; `Host.viewOf` and `Host.pointerOf` decode the `inkproof-view` and `inkproof-pointer` details.

## [0.12.0]

- The `cursor` attribute draws lines at the data position under the pointer, shown on the other charts of the group too; `CursorMode` and `Cursor.lines` are the pure parts.
- The `select` attribute makes a drag on a chart draw, move or resize a band over its x range, reported as `inkproof-select` and set with `Host.setSelection`; the group's other charts show the band as their x range; `SelectMode` and `Select` are the pure parts, on Viewport v0.10.0's `Selection`.

## [0.11.0]

- The `group` attribute links chart elements: those with the same name follow one another's x range from pointer and key input, and one that drops or changes the attribute stops following.

## [0.10.0]

- The `drag` attribute (`pan` by default, or `box`) makes a plain drag draw the box zoom and shift-drag pan; `DragMode` is the pure choice.

## [0.9.1]

- Requires Gpu v0.10.0 and regenerates `gpu-js` from it, so pixel-size strokes and markers draw.

## [0.9.0]

- The `box-zoom` and `box-min` attributes choose which axes a shift-drag box zooms and the least drag that counts; `BoxConfig` is the pure choice, over Viewport's `Gesture.boxOver` (v0.7.0).

## [0.8.0]

- `Access.plotOrigin` says where the plot lies in the element; pointer positions are taken from it, and a pointer outside the plot starts no gesture and reports no position.

## [0.7.0]

- `Host.setScene` replaces a chart's scene keeping its `Nav`, and `Host.apply` applies a `Command` to a chart, with `Nav.clamp` keeping the cursor inside the new data.

## [0.6.2]

- `Label.ofPlaced` and `Label.ofDrawing` turn Scene's placed axis labels into `Host.Label`s; Web requires Scene v0.11.0 and Axis v0.6.0.

## [0.6.1]

- A `Host.Label` has an alignment, a baseline and a rotation, drawn by the Canvas 2D layer.

## [0.6.0]

- The pointer gesture conversions come from Viewport's `Gesture`; `Pointer` and `Px` are removed from Web.

## [0.5.0]

- The chart zooms, pans and box-zooms from a wheel, drag or pinch, and reports the data position under the pointer as `inkproof-pointer`.
- When the last chart is removed the host deletes the buffers and programs it still holds.

## [0.4.9]

- The host keeps interpreter state between draws, so command lists may draw buffers uploaded earlier, and reports context restoration.

## [0.4.8]

- Tile queries read the clock once every 32 steps instead of three boundary crossings on every step.

## [0.4.7]

- Tile queries yield to the event loop after 8 ms of work instead of after every tile.

## [0.4.6]

- `Host.TileCache` is now `TileCache M`, keeps decoded tiles, and lets queries running at once share one fetch per tile.

## [0.4.5]

- Adds `Host.TileCache`, a bounded least-recently-used cache of fetched tiles that `queryTiles`, `queryColumns` and `queryColumnsFrom` take as an optional argument.

## [0.4.4]

- Adds `Host.queryColumnsFrom`, per-column aggregates over a pyramid stored from level `k0`, with the leaves read from raw files by byte range.

## [0.4.3]

- Adds `Host.queryColumns`, per-column aggregates over a tiled pyramid; requires Core v0.11.0.

## [0.4.2]

- Adds `Host.fetchTile`, fetching a tile with an optional byte range; `queryTiles` uses it.

## [0.4.1]

- Interprets Gpu v0.5.0's scissor command; requires Gpu v0.5.0.

## [0.4.0]

- Keyboard control (zoom, pan, cursor, series) and accessible summaries and data tables on the chart element.

## [0.3.0]

- Tile queries use Core's `Aggregate.foldTilesM`; Web's own copy is removed.

## [0.2.0]

- Tile queries that fetch and aggregate with Core's aggregation, one tile at a time without blocking the main thread.

## [0.1.0]

- A custom element that hosts Gpu's generated interpreter on one shared WebGL2 context with a Canvas 2D text layer, follows resizes, device pixel ratio changes and context loss, and reports invalid attributes.
- Browser text measurements for Axis, cached by font and text.
