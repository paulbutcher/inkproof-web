# Inkproof.Web

The browser host of Inkproof: a custom element that draws a chart on a shared WebGL2 context with a Canvas 2D text layer, written in Lean under Lasm with no hand-written JavaScript beyond a minimal shim. Part of Inkproof. Released under the Apache 2.0 license; see `LICENSE`.

## Requiring it

```lean
require «inkproof-web» from git "https://github.com/paulbutcher/inkproof-web" @ "v0.4.8"
```

Modules that import Lasm (`Inkproof.Web.Host.*`) build only under Lasm's browser target; the rest build natively. See `DESIGN.md`.

## What it does

- Draw an Inkproof chart in a web page as a custom element, run on one WebGL2 context shared by every chart, recovered after a lost context: `Inkproof.Web.Host.register`.
- Redraw only when something changed, never while idle: `Frame`, `Frame.invalidate`, `Frame.shouldDraw`.
- Size the drawing surface to the device pixel ratio: `Size`, `backingPx`.
- Measure text once per font and string: `TextCache`.
- Read and validate the element's attributes, reporting bad ones instead of defaulting them: `ChartAttrs.parse`.
- Log to the browser console at a threshold, warn by default: `Level`, `Level.parse?`, `Level.enabled`.
- Control a chart from the keyboard (zoom, pan, cursor, series): `Command.ofKey`, `Nav`, `Nav.apply`, `NavConfig`.
- Describe a chart for assistive technology, with a name, a summary, a cursor reading and a data table: `Access`, `Access.summaryText`, `Access.cursorText`.
- Format numbers and lines of text for those descriptions: `showFloat`, `formatLine`, `describe`.
- Fetch a tile, or a byte range of a file, with the status checked and a failure logged: `Host.fetchTile`.
- Aggregate a range of nodes over tiles fetched one at a time without blocking the page: `Host.queryTiles`.
- Share decoded tiles, and in-flight fetches, between concurrent queries, bounded and least recently used first: `Host.TileCache.new`, passed to `queryTiles`, `queryColumns` and `queryColumnsFrom`.
- Aggregate each of a chart's pixel columns over a tiled pyramid, fetching each tile once: `Host.queryColumns`.
- The same for a pyramid stored only from level `k0` up, reading the finest zooms from raw files by byte range: `Host.queryColumnsFrom`.
