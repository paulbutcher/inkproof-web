# Changelog

## [0.4.10]

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
