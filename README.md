# ipu-model-kernels

IPU kernels for the layers of popular models, and the database of how much of each
model the IPU can run. Written by [ipu-kernelgen](../ipu-kernelgen); do not edit by hand.

| path | what |
|---|---|
| `kernels/zoo/<name>/` | generated kernels: `.asm` template, `kernel.toml`, `reference.py`, `BUILD.bazel`, and `kernelgen.toml` (kind, method, hardware-clean, host steps). Each passed `bazel test` in an ipu-emulator worktree before it was kept. |
| `db/zoo.sqlite` | the database (schema: `ipu_kernelgen/db.py`) |
| `db/export/*.json` | the same tables as sorted JSON, so every change shows in a diff |
| `reports/COVERAGE.md` | per model: share of MACs and calls on chip / chip+host / emulator-only / CPU; gaps by op; kernels; approximation catalogue; accuracy |
| `reports/models/*.md` | per model and scenario: every layer, its calls, MACs and implementations |

## Using the kernels in ipu-emulator

Copy `kernels/zoo` into an ipu-emulator checkout as `kernels/zoo`, add
`"zoo": [<folder names>]` to `KERNELS` in `kernels/families.bzl`, then
`bazel test //kernels/zoo/...`.

## Tables

- `models`: each surveyed model (domain, family, size, parameters at full depth, depth scaling)
- `layers`: each distinct layer signature, `op{param=value,...}`, with MACs per call
- `model_layers`: which model runs which signature, how often per forward, in which scenario
  (`prefill`, `decode` with a KV cache, `forward`)
- `kernels`: every kernel of ipu-emulator and of this repo, its formats, hardware-cleanliness,
  kind and method
- `implementations`: per signature, every kernel that accepts it (registry routing), with its
  **placement** (`chip`, `chip+host`, `chip-emu`, `cpu`) and **kind** (`exact`,
  `approximation`, `estimation`, `variation`); the view `layer_best` ranks them
- `approximations`: qbench.ipu's catalogue of realisations per op, with op-level error
- `accuracy`: whole-model accuracy (qbench, real weights and data) of each realisation and of
  the full chip realisation, against the exact FP32 model
- `generation_runs`: every agent run: target signatures, agent, attempts, time, cost, result
