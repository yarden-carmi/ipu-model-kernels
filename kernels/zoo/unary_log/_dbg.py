"""unary_log's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/unary_log:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/unary_log`` are the checks).
"""

import sys
from pathlib import Path

import numpy as np

from ipu_emu.reference import ReferenceModel
from ipu_harness.abi import apply, register_writes
from ipu_harness.assembly import assemble
from ipu_harness.cases import expand
from ipu_harness.manifest import load_manifest
from ipu_harness.packing import pack, region_fill, stored_rows, unpack
from ipu_harness.params import plan_case
from ipu_harness.placement import place
from ipu_isa.codec.disasm import disassemble

from reference import reference

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "dynamic"
SHOW = len(sys.argv) > 3

manifest = load_manifest(Path("kernels/zoo/unary_log"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {"x": rng.uniform(0.5, 2.0, plan.shapes["x"])}

placement = place(plan, {name: stored_rows(t, plan) for name, t in tensors.items()})
model = ReferenceModel(plan.format.mode)
words = tuple(assemble(plan).words)
model.load_program(words)
row_bytes = plan.format.row_bytes

for name, values in arrays.items():
    packed = pack(tensors[name], values, plan)
    base = placement.region(name).base_row * row_bytes
    model.write_xmem(base, packed.data)
    for index, meta in enumerate(packed.metadata or ()):
        model.write_xmem_metadata(base + index * row_bytes, meta)

for name in ("maskr",):
    if name in tensors:
        packed = region_fill(tensors[name], plan, placement.region(name).rows)
        base = placement.region(name).base_row * row_bytes
        model.write_xmem(base, packed.data)
        for index, meta in enumerate(packed.metadata or ()):
            model.write_xmem_metadata(base + index * row_bytes, meta)

apply(model, tuple(register_writes(plan, placement)))

print("derived:", dict(plan.derived))
print("CR:", {i: model.read_register("cr", i) for i in range(16)})
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
if SHOW:
    for pc, word in enumerate(words):
        print(f"  {pc:3d} {disassemble(word)}")

model.run(5_000_000)
region = placement.region("y")
data = model.read_xmem(region.base_row * row_bytes, region.rows * row_bytes)
meta = (
    None
    if not plan.format.nx8
    else tuple(
        model.read_xmem_metadata((region.base_row + i) * row_bytes) for i in range(region.rows)
    )
)
got = unpack(tensors["y"], data, plan, meta)
want = reference(**arrays, **{k: v for k, v in p.items()})["y"]

print("status:", model.status, "cycles:", model.stats().cycles)
g = np.asarray(got).reshape(-1)
w = want.reshape(-1)
n = int(p["numel"])
diffs = np.abs(np.diff(np.unique(g[: min(n, 4096)]))) if n > 1 else np.array([1.0])
steps = diffs.min() if diffs.size else 1.0
err = np.abs(g[:n] - w[:n])
print("max|err| =", err.max(), " approx grid step =", steps, " err/step =", err.max() / steps)
for i in range(rows_ := -(-n // 128)):
    lo, hi = i * 128, min(n, (i + 1) * 128)
    e = np.abs(g[lo:hi] - w[lo:hi])
    print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={e.max():g} bad={(e > 0.02).sum()}")
print("row 0 got ", np.round(g[:6], 5))
print("row 0 want", np.round(w[:6], 5))
