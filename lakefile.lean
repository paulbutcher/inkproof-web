/-
Copyright (c) 2026 Paul Butcher. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lake
open Lake DSL

package «inkproof-web» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩,
    ⟨`warningAsError, true⟩
  ]

require «inkproof-gpu» from git "https://github.com/paulbutcher/inkproof-gpu" @ "v0.22.0"
require «inkproof-viewport» from git "https://github.com/paulbutcher/inkproof-viewport" @ "v0.10.1"
require «inkproof-scale» from git "https://github.com/paulbutcher/inkproof-scale" @ "v0.9.0"
require «inkproof-axis» from git "https://github.com/paulbutcher/inkproof-axis" @ "v0.14.0"
require «inkproof-scene» from git "https://github.com/paulbutcher/inkproof-scene" @ "v0.32.0"
require «inkproof-core» from git "https://github.com/paulbutcher/inkproof-core" @ "v0.13.0"

@[default_target]
lean_lib InkproofWeb where
  roots := #[`Inkproof.Web]

@[test_driver]
script tests do
  let child ← IO.Process.spawn
    { cmd := "lake", args := #["test"], cwd := __dir__ / "test" }
  child.wait
