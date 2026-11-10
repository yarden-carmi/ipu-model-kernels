"""layout's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/layout_concat:dbg -- [case] [format] [anything-for-a-dump]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/layout_concat`` are the checks).
"""

import sys
from pathlib import Path

import numpy as np
from reference import reference

from ipu_emu.reference import ReferenceModel
from ipu_harness.abi import apply, register_writes
from ipu_harness.assembly import assemble
from ipu_harness.cases import expand
from ipu_harness.manifest import load_manifest
from ipu_harness.packing import pack, region_fill, stored_rows, unpack
from ipu_harness.params import plan_case
from ipu_harness.placement import place
from ipu_isa.codec.disasm import disassemble

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "dynamic"
SHOW = len(sys.argv) > 3

manifest = load_manifest(Path("kernels/zoo/layout_concat"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {
    "a": rng.uniform(-1, 1, plan.shapes["a"]),
    "b": rng.uniform(-1, 1, plan.shapes["b"]),
}

placement = place(plan, {name: stored_rows(t, plan) for name, t in tensors.items()})
model = ReferenceModel(plan.format.mode)
words = tuple(assemble(plan).words)
model.load_program(words)
row_bytes = plan.format.row_bytes


def write(name, packed):
    """A region's rows and, in NX8, each row's metadata word."""
    base = placement.region(name).base_row * row_bytes
    model.write_xmem(base, packed.data)
    for index, word in enumerate(packed.metadata or ()):
        model.write_xmem_metadata(base + index * row_bytes, word)


for name, values in arrays.items():
    write(name, pack(tensors[name], values, plan))
write("maskr", region_fill(tensors["maskr"], plan, placement.region("maskr").rows))

apply(model, tuple(register_writes(plan, placement)))

print("params:", dict(p))
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
stats = model.stats()

print(
    "status:",
    model.status,
    "cycles:",
    stats.cycles,
    "MAC util:",
    stats.effective_mac_utilization,
)
print("R0:", bytes(model.read_register("r", 0)[:8]).hex())
print("R_MASK:", bytes(model.read_register("r_mask", 0)[:8]).hex())
print(
    "y row 0:",
    bytes(model.read_xmem(region.base_row * row_bytes, 8)).hex(),
    hex(model.read_xmem_metadata(region.base_row * row_bytes)),
)
print("a row 0:", bytes(model.read_xmem(0, 8)).hex(), hex(model.read_xmem_metadata(0)))
n = int(p["numel"])
g = np.asarray(got).reshape(-1)
w = np.asarray(want, dtype=np.float64).reshape(-1)
print("max|err| =", np.abs(g - w).max())
for i in range(min(region.rows, 6)):
    lo, hi = i * 128, min(n, (i + 1) * 128)
    err = np.abs(g[lo:hi] - w[lo:hi])
    print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={err.max():g} bad={(err > 0.02).sum()}")
print("row 0 got ", np.round(g[:6], 4))
print("row 0 want", np.round(w[:6], 4))
print("last row got ", np.round(g[-6:], 4))
print("last row want", np.round(w[-6:], 4))
