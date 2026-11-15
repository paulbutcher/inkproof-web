# Inkproof.Web design

## Layout

Lasm's browser bindings (`Lasm.JS.Web`, `Lasm.UI`) ship with `@lasm/cli` and are not a Lake dependency, so modules that import them cannot build natively. Everything that does not need the browser (surface sizing, redraw state, log levels) lives in modules that do not import Lasm, and is proved and tested natively with `lake`; the browser host is built by `lasm build --target browser`.
