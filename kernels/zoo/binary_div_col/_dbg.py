"""binary_div_col's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/binary_div_col:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/binary_div_col`` are the checks).
"""

import sys
from pathlib import Path

import numpy as np

from ipu_emu.reference import ReferenceModel
from ipu_harness.abi import apply, register_writes
from ipu_harness.assembly import assemble
from ipu_harness.cases import expand
from ipu_harness.manifest import load_manifest
from ipu_harness._codec import decode_rows, encode_rows
from ipu_harness.packing import pack, stored_rows, unpack
from ipu_harness.params import plan_case
from ipu_harness.placement import place
from ipu_isa.codec.disasm import disassemble

from reference import reference

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "dynamic"
SHOW = len(sys.argv) > 3

manifest = load_manifest(Path("kernels/zoo/binary_div_col"))
case = next(c for c in expand(manifest) if c.name == CASE or c.name.startswith(CASE + "["))
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {
    "a": rng.uniform(-1, 1, plan.shapes["a"]),
    "b": rng.uniform(0.25, 4, plan.shapes["b"]),
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
    arrays[name] = np.asarray(
        unpack(tensors[name], packed.data, plan, packed.metadata), dtype=np.float64
    ).reshape(plan.shapes[name])

for name in ("maskr", "twos", "rcp", "u", "e"):
    if name in tensors:
        rows = placement.region(name).rows
        value = 2.0 if name == "twos" else 0.5
        if name == "maskr":
            data, metadata = b"\xff" * (rows * row_bytes), None
        else:
            data, metadata = encode_rows(
                np.full((rows, 128), value, dtype=np.float64), plan.format
            )
        base = placement.region(name).base_row * row_bytes
        model.write_xmem(base, data)
        for index, meta in enumerate(metadata or ()):
            model.write_xmem_metadata(base + index * row_bytes, meta)

apply(model, tuple(register_writes(plan, placement)))

print("derived:", dict(plan.derived))
print("CR:", {i: model.read_register("cr", i) for i in range(16)})
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
for name in ("a", "b"):
    if name in tensors:
        r = placement.region(name)
        n = min(r.rows, 2)
        d = model.read_xmem(r.base_row * row_bytes, row_bytes)
        m = (
            None
            if not plan.format.nx8
            else (model.read_xmem_metadata(r.base_row * row_bytes),)
        )
        vals = np.asarray(
            decode_rows(d[:row_bytes], plan.format, m), dtype=np.float64
        ).reshape(-1)
        print(f"{name}:", np.round(vals[: min(128, int(p["numel"]) if name == "a" else int(p["inner"]))], 6))
for name in ("rcp", "u", "e"):
    if name in tensors:
        r = placement.region(name)
        d = model.read_xmem(r.base_row * row_bytes, row_bytes)
        m = (
            None
            if not plan.format.nx8
            else (model.read_xmem_metadata(r.base_row * row_bytes),)
        )
        vals = np.asarray(
            decode_rows(d[:row_bytes], plan.format, m), dtype=np.float64
        ).reshape(-1)
        print(f"{name}:", np.round(vals[: max(int(p["inner"]), 8)], 6))
if SHOW:
    for pc, word in enumerate(words):
        print(f"  {pc:3d} {disassemble(word)}")
model.run(50_000_000)
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
for name in ("rcp", "u", "e"):
    r = placement.region(name)
    d = model.read_xmem(r.base_row * row_bytes, row_bytes)
    m = (model.read_xmem_metadata(r.base_row * row_bytes),) if plan.format.nx8 else None
    vals = np.asarray(decode_rows(d[:row_bytes], plan.format, m), dtype=np.float64).reshape(-1)
    print(f"pre {name}:", np.round(vals[: max(int(p["inner"]), 8)], 6))
yreg = placement.region("y")
print(
    "y bytes:",
    bytes(model.read_xmem(yreg.base_row * row_bytes, 8)).hex(),
    hex(model.read_xmem_metadata(yreg.base_row * row_bytes)),
)
g = np.asarray(got).reshape(-1)
w = want.reshape(-1)
err = np.abs(g - w)
print("max|err| =", err.max())
for i in range(min(int(p["inner"]), 4)):
    lo, hi = i * int(plan.derived["rowlen"]), min(int(p["numel"]), (i + 1) * int(plan.derived["rowlen"]))
    e = err[lo:hi]
    print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={e.max():g} bad={(e > 0.02).sum()}")
print("row 0 got ", np.round(g[: plan.derived["rowlen"]], 4))
print("row 0 want", np.round(w[: plan.derived["rowlen"]], 4))
print("last row got ", np.round(g[-plan.derived["rowlen"]:], 4))
print("last row want", np.round(w[-plan.derived["rowlen"]:], 4))
