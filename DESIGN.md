# Inkproof.Web design

## Layout

Lasm's browser bindings (`Lasm.JS.Web`, `Lasm.UI`) ship with `@lasm/cli` and are not a Lake dependency, so modules that import them cannot build natively. Everything that does not need the browser (surface sizing, redraw state, log levels, attribute validation, the text cache) lives in modules that do not import Lasm, and is proved and tested natively with `lake`; they are the library `InkproofWeb` and the only modules in `API.lock`. The host is `Inkproof.Web.Host.*`, imported by the application that Lasm builds; `Inkproof.Web.Host.register` defines a chart element.

## Host

- One WebGL2 context, on a canvas that is never attached, serves every chart: a chart sizes it, runs the command list, and copies the result to its own 2D canvas, then draws its text over it. Only the encoded command list crosses to JavaScript, once per redraw. The interpreter's state lives as long as the context, so a list may draw buffers and programs an earlier list uploaded; handles are page-wide, so charts must not give one handle two meanings.
- A chart redraws only when invalidated: a new scene, a resize, a change of device pixel ratio or a restored context. Nothing is scheduled while it is idle.
- Resizes come from a `ResizeObserver` and ratio changes from the media query that names the current ratio, both bound from Lean. A lost context is kept restorable by cancelling the event and its interpreter state is discarded; `contextGeneration` increases and each chart dispatches `inkproof-contextrestored` (detail `generation`) before redrawing, so the consumer must answer with a list built as for a fresh context. When the last chart disconnects the host releases every buffer and program that remains and increases the generation, so a chart connected later starts fresh.
- Pointer input becomes Viewport `Input`s through pure functions in `Pointer` and `Nav.input`: wheel zooms about the pointer, drag pans, shift-drag zooms to a box, two pointers pinch. `inkproof-pointer` reports the data position while over the plot; the element sets `touch-action: none`.
- Attributes are `src` (a URL of an encoded command list, or whatever the registered loader makes of it) and `log-level`. Invalid ones are logged and dispatched as `inkproof-error`; each redraw dispatches `inkproof-draw` with the backing size.
- Fetching runs as `Async` on the main thread, which never blocks; Lean in Lasm's browser target is single-threaded, so there is no worker. Tile queries (`queryTiles`, and `queryColumns` for one aggregate per pixel column) fetch each tile with `fetchTile`, which takes an optional byte range, and only the tiles a range touches, one at a time, merge them with Core's aggregation (`Aggregate.foldTilesM`, which is `foldTiles` with the fetch in a monad), and yield to the event loop after each tile, so a long query never holds the main thread. A failed tile is logged with its URL and fails the query. A `TileCache M` passed to a query keeps the decoded tiles and byte ranges, at most a stated number, least recently used evicted, so queries sharing it fetch and decode each once; queries running at once that need the same tile share one fetch, and a failed one is logged once, fails each waiter and is never stored. `queryColumnsFrom` serves a pyramid stored from level `k0`: columns at least `branching ^ k0` leaves wide come from the stored levels, narrower ones from leaves the application's source maps to raw byte ranges, a leaf in no range being a gap. A worker is not used: it would need a second Lasm build and a second shim. Text measurement is `Canvas 2D measureText`, cached by font and text. A text that could not be measured is NaN, which Axis drops rather than places.

## Accessibility

- A scene carries an `Access`: the chart's name, series, point count, optional summary, a data table and the view configuration. The element becomes focusable (`tabindex` 0 unless set), takes the name as `aria-label` and the summary as `aria-description`, and holds the data in a visually hidden table; the `show-table` attribute swaps the canvas for it.
- Keys map to a `Command` (pure, native), and `Nav.apply` applies it: zoom and pan go through Viewport's `View.step`, so keys and pointer share one path. The host reports changes as `inkproof-view` and `inkproof-cursor` events and announces them in a polite live region; the application answers a view change with a new scene. Keys with modifiers, and keys the chart does not use, are left to the browser.

## Building an application

An application's `package.json` depends on `gpu-js` (the module `inkproof-gpu-js`, a copy of the interpreter the pinned Gpu release generates, written by `scripts/gpu-module.sh <dir>` and checked by the tests) and on `shim/inkproof-web-element` (the shim below), both by `file:` path. Lasm resolves them through Vite and `@lasm/cli/vite`; a static `lasm build` cannot resolve npm modules. `test/` is a working example.

## Trusted computing base

| Shim | Lines | Why | Upstream |
| --- | --- | --- | --- |
| `shim/inkproof-web-element/index.js` | 10 | Lean cannot define a class extending `HTMLElement`; the class only forwards its lifecycle callbacks to Lean functions | tentenths/inkproof-coordination#113 |

Not shims: `inkproof-gpu-js` is Gpu's generated output, and the Vite page glue and `vite.config.js` under `test/` build the test pages.
