"""unary's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/unary_silu:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/unary_silu`` are the checks).
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

manifest = load_manifest(Path("kernels/zoo/unary_silu"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

from ipu_harness.cases import inputs_for  # noqa: E402

arrays = dict(inputs_for(case, plan).tensors)

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

print("params:", dict(p))
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
print("CR:", {i: model.read_register("cr", i) for i in range(16)})
if SHOW:
    for pc, word in enumerate(words):
        print(f"  {pc:3d} {disassemble(word)}")

model.run(5_000_000)

for name in ("t", "e", "q", "w", "one"):
    if name not in placement.regions:
        continue
    reg = placement.region(name)
    d = model.read_xmem(reg.base_row * row_bytes, reg.rows * row_bytes)
    m = tuple(
        model.read_xmem_metadata((reg.base_row + i) * row_bytes) for i in range(reg.rows)
    )
    v = np.asarray(unpack(tensors[name], d, plan, m)).reshape(-1)
    print(f"{name}: base={reg.base_row} meta={hex(m[0])} first={np.round(v[:6], 5)}")

region = placement.region("y")
data = model.read_xmem(region.base_row * row_bytes, region.rows * row_bytes)
meta = tuple(
    model.read_xmem_metadata((region.base_row + i) * row_bytes) for i in range(region.rows)
)
got = unpack(tensors["y"], data, plan, meta)
want = reference(**arrays, **{k: v for k, v in p.items()})["y"]

print("x row0   ", np.round(np.asarray(arrays["x"]).reshape(-1)[:6], 5))
print("status:", model.status, "cycles:", model.stats().cycles)
print("shapes:", dict(plan.shapes), "numel:", int(p["numel"]), "x.size", np.asarray(arrays["x"]).size)
_xr = placement.region("x")
_raw = model.read_xmem(_xr.base_row * row_bytes, _xr.rows * row_bytes)
_met = tuple(model.read_xmem_metadata((_xr.base_row + i) * row_bytes) for i in range(_xr.rows))
from ipu_harness.packing import decode_rows  # noqa: E402

print("x stored:", np.round(decode_rows(_raw, plan.format, _met)[1][:8], 5))
g = np.asarray(got).reshape(-1)
w = np.asarray(want).reshape(-1)
print("max|err| =", np.abs(g - w).max())
n = int(p["numel"])
rows = -(-n // 128)
for i in range(min(rows, 4)):
    lo, hi = i * 128, min(n, (i + 1) * 128)
    err = np.abs(g[lo:hi] - w[lo:hi])
    print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={err.max():g} bad={(err > 0.02).sum()}")
print("row 0 got ", np.round(g[:6], 4))
print("row 0 want", np.round(w[:6], 4))
