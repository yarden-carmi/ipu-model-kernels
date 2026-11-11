"""Scratch probe: step the default case and watch R_ACC / MULT_RES."""

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

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
STEPS = int(sys.argv[2]) if len(sys.argv) > 2 else 20

manifest = load_manifest(Path("kernels/zoo/gemm"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, "dynamic", case=case.decl)
tensors = plan.manifest.tensors

rng = np.random.default_rng(0)
arrays = {
    "a": rng.uniform(-1, 1, plan.shapes["a"]),
    "w": rng.uniform(-1, 1, plan.shapes["w"]),
    **({"b": rng.uniform(-1, 1, plan.shapes["b"])} if "b" in plan.shapes else {}),
}

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

packed = region_fill(tensors["maskr"], plan, placement.region("maskr").rows)
model.write_xmem(placement.region("maskr").base_row * row_bytes, packed.data)

apply(model, tuple(register_writes(plan, placement)))

rec = model.step()  # words 0..3: prologue
for pc in range(3):
    rec = model.step()
print("LRs:", [model.read_register("lr", i) for i in range(16)])
for i in range(STEPS):
    rec = model.step()
    acc = np.frombuffer(model.read_register("r_acc", 0), dtype=np.float32)
    lrs = [model.read_register("lr", i) for i in range(16)]
    if i >= STEPS - 30:
        yrow = placement.region("y").base_row * row_bytes
        print(f"step {i}: lr={lrs} acc[:3]={acc[:3]} yrow={bytes(model.read_xmem(yrow, 8)).hex()}")
