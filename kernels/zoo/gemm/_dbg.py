"""gemm's debug helper: run one case and print its rows against the reference.

    python3 kernels/zoo/gemm/_dbg.py [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/gemm`` are the checks).
"""

import sys
from pathlib import Path

import numpy as np

from ipu_emu.reference_model import ReferenceModel
from ipu_harness.abi import apply, register_writes
from ipu_harness.assembly import assemble
from ipu_harness.cases import expand
from ipu_harness.manifest import load_manifest
from ipu_harness.packing import pack, stored_rows, unpack
from ipu_harness.params import plan_case
from ipu_harness.placement import place

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "e4"

manifest = load_manifest(Path("kernels/zoo/gemm"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params
m, k, n = p["m"], p["k"], p["n"]

rng = np.random.default_rng(0)
arrays = {"a": rng.uniform(-1, 1, (m, k)), "w": rng.uniform(-1, 1, (n + 1, k))}
if "b" in tensors:
    arrays["b"] = rng.uniform(-1, 1, (1, n))

placement = place(plan, {name: stored_rows(t, plan) for name, t in tensors.items()})
model = ReferenceModel(plan.format.mode)
model.load_program(tuple(assemble(plan).words))
row_bytes = plan.format.row_bytes

for name, values in arrays.items():
    packed = pack(tensors[name], values, plan)
    base = placement.region(name).base_row * row_bytes
    model.write_xmem(base, packed.data)
    for index, meta in enumerate(packed.metadata or ()):
        model.write_xmem(base + index * row_bytes, meta)
apply(model, tuple(register_writes(plan, placement)))

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
want = arrays["a"][:, :k] @ arrays["w"][:n, :k].T
if "b" in arrays:
    want = want + arrays["b"][:, :n]

print("status:", model.status, "cycles:", model.stats().cycles)
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
print("max|err| =", np.abs(got - want).max())
for i in range(min(m, 3)):
    print(f"row {i} got ", np.round(got[i, : min(n, 6)], 4))
    print(f"row {i} want", np.round(want[i, : min(n, 6)], 4))
