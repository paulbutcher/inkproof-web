#!/usr/bin/env bash
# Copyright (c) 2026 Paul Butcher. All rights reserved.
# Released under Apache 2.0 license as described in the file LICENSE.
# Packages the interpreter that the pinned Gpu release generates as the npm module `inkproof-gpu-js`,
# in the directory given, so that a Lasm browser build can bind its exports. `gpu-js/` is the committed output;
# the tests fail if it differs from the pinned release.
set -euo pipefail
out="${1:?usage: gpu-module.sh <output directory>}"
gpu="$(cd "$(dirname "$0")/.." && pwd)/.lake/packages/inkproof-gpu"
mkdir -p "$out"
cp "$gpu/generated/gpu.js" "$out/index.js"
printf '{\n  "name": "inkproof-gpu-js",\n  "version": "0.0.0",\n  "private": true,\n  "type": "module",\n  "main": "index.js"\n}\n' > "$out/package.json"
