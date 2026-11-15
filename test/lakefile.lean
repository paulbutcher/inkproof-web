/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lake
open Lake DSL

package «inkproof-web-test» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩,
    ⟨`warningAsError, true⟩
  ]

require «inkproof-web» from ".."
require «inkproof-tools» from git "https://github.com/paulbutcher/inkproof-tools" @ "v0.2.1"

@[default_target]
lean_exe tests where
  root := `Main

lean_lib InkproofWebTest where
  globs := #[.submodules `InkproofWebTest]

lean_exe genchart where
  root := `GenChart

/-- The native and Lasm tests, then the browser tests when Playwright is installed. -/
@[test_driver]
script test do
  let driver ← IO.Process.spawn
    { cmd := "lake", args := #["exe", "inkproof-tools/inkproof-test-driver"], cwd := __dir__ }
  let code ← driver.wait
  if code != 0 then return code
  unless ← (__dir__ / "node_modules" / "playwright").pathExists do
    IO.eprintln "::warning::Browser tests skipped: run `npm ci` in test/"
    return 0
  let steps := #[("gpu-js", "bash", #["-c", "d=$(mktemp -d) && ../scripts/gpu-module.sh $d && diff -r $d ../gpu-js"]),
    ("web", "lake", #["exe", "genchart", "web/public/chart.bin"]),
    ("build", "npx", #["vite", "build"]), ("browser", "node", #["--test", "browser.test.mjs"])]
  for (name, cmd, args) in steps do
    IO.println s!"== {name}"
    let child ← IO.Process.spawn { cmd, args, cwd := __dir__, env := #[("LASM_EDITOR", some "0")] }
    let code ← child.wait
    if code != 0 then return code
  return 0
