"""unary_exp's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/unary_exp:dbg -- [case] [format] [anything-for-a-dump]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/unary_exp`` are the checks).
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

manifest = load_manifest(Path("kernels/zoo/unary_exp"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {"x": rng.uniform(-8, 8, plan.shapes["x"])}

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
print("max|err| =", np.abs(np.asarray(got).reshape(-1) - want.reshape(-1)).max())
g = np.asarray(got).reshape(-1)
print("row 0 got ", np.round(g[:6], 4))
print("row 0 want", np.round(want.reshape(-1)[:6], 4))
