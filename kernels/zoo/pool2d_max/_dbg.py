"""pool2d_max's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/pool2d_max:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/pool2d_max`` are the checks).
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

manifest = load_manifest(Path("kernels/zoo/pool2d_max"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {"x": rng.uniform(-1, 1, plan.shapes["x"])}

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
print(
    "LR:",
    {
        i: (lambda v: v if isinstance(v, int) else int.from_bytes(v, "little"))(
            model.read_register("lr", i)
        )
        for i in range(16)
    },
)
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
if SHOW:
    for pc, word in enumerate(words):
        print(f"  {pc:3d} {disassemble(word)}")

trace_kw = {}
if len(sys.argv) > 4 and sys.argv[4] == "trace":
    from ipu_emu.trace import TraceWriter

    _tw = TraceWriter("/tmp/trace.json", model.trace_header())
    trace_kw = {"trace": _tw}
model.run(5_000_000, **trace_kw)
if trace_kw:
    _tw.close()
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
if len(sys.argv) > 4 and sys.argv[4] == "trace":
    import json as _json

    for line in open("/tmp/trace.json"):
        rec = _json.loads(line)
        slots = [s["mnemonic"] for s in rec.get("slots", [])]
        if rec.get("cycle") is None or rec["cycle"] > 30 or rec["cycle"] < 17:
            continue
        for rw in rec.get("reg_writes", []):
            d = rw.get("data")
            print(
                "  w",
                rec["cycle"],
                rw["register"],
                rw.get("index"),
                rw.get("offset"),
                (d or "").encode("latin1").hex()[:64],
            )
        print(rec["cycle"], rec["pc_before"], slots)
        for rw in rec.get("reg_writes", []):
            d = rw.get("data")
            print("   ", rw["register"], rw.get("index"), rw.get("offset"), (d or "")[:32])
print("R_ACC:", np.frombuffer(model.read_register("r_acc", 0), dtype=np.float32)[:4])
print("R0:", bytes(model.read_register("r", 0)[:8]).hex())
print("R1:", bytes(model.read_register("r", 1)[:8]).hex())
print("R_CYCLIC:", bytes(model.read_register("r_cyclic", 0)[:8]).hex())
print("R_MASK:", bytes(model.read_register("r_mask", 0)[:8]).hex())
yreg = placement.region("y")
print(
    "y bytes:",
    bytes(model.read_xmem(yreg.base_row * row_bytes, 8)).hex(),
    hex(model.read_xmem_metadata(yreg.base_row * row_bytes)),
)
print(
    "x bytes:",
    bytes(model.read_xmem(0, 8)).hex(),
    hex(model.read_xmem_metadata(0)),
)
g = np.asarray(got).reshape(-1)
wv = want.reshape(-1)
print("max|err| =", np.abs(g - wv).max() if len(g) else "empty")
rows = -(-len(g) // 128)
for i in range(min(rows, 4)):
    lo, hi = i * 128, min(len(g), (i + 1) * 128)
    if hi > lo:
        err = np.abs(g[lo:hi] - wv[lo:hi])
        print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={err.max():g} bad={(err > 0.02).sum()}")
print("row 0 got ", np.round(g[:8], 4))
print("row 0 want", np.round(wv[:8], 4))
