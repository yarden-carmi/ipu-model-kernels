"""row_norm's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/row_norm_layernorm:dbg -- [case] [format] [anything-for-a-dump]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/row_norm_layernorm`` are the checks).
"""

import os
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
from ipu_isa.nx8 import split_metadata

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "dynamic"
SHOW = len(sys.argv) > 3
ROW = int(os.environ.get("DBG_ROW", "0"))

manifest = load_manifest(Path("kernels/zoo/row_norm_layernorm"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params
rows, channels, kind, eps = p["rows"], p["channels"], p["kind"], p["eps"]
chunks = -(-channels // 128)

rng = np.random.default_rng(0)
arrays = {
    "x": rng.uniform(-1, 1, (rows, channels)),
    "gamma": rng.uniform(-1, 1, (channels,)),
    "beta": rng.uniform(-1, 1, (channels,)),
}

placement = place(plan, {n: stored_rows(t, plan) for n, t in tensors.items()})
model = ReferenceModel(plan.format.mode)
words = tuple(assemble(plan).words)
model.load_program(words)
row_bytes = plan.format.row_bytes

for name, t in tensors.items():
    reg = placement.region(name)
    packed = pack(t, arrays[name], plan) if name in arrays else region_fill(t, plan, reg.rows)
    base = reg.base_row * row_bytes
    model.write_xmem(base, packed.data)
    for i, meta in enumerate(packed.metadata or ()):
        model.write_xmem_metadata(base + i * row_bytes, meta)
apply(model, tuple(register_writes(plan, placement)))

if SHOW:
    lo, hi = (int(v) for v in os.environ.get("DBG_PC", "0 10000").split())
    for pc, word in enumerate(words):
        if lo <= pc < hi:
            print(f"  {pc:3d} {disassemble(word)}")
    print("R_CYCLIC:", bytes(model.read_register("r_cyclic", 0)[:16]).hex())
    print("R0:", bytes(model.read_register("r", 0)[:16]).hex())
    print("R1:", bytes(model.read_register("r", 1)[:16]).hex())
    print("R_MASK:", bytes(model.read_register("r_mask", 0)[:16]).hex())
    print(
        "invn row bytes:",
        bytes(model.read_xmem(placement.region("invn").base_row * row_bytes, 16)).hex(),
    )
    print(
        "epsr row bytes:",
        bytes(model.read_xmem(placement.region("epsr").base_row * row_bytes, 16)).hex(),
    )
    print(
        "x row0 bytes:",
        bytes(model.read_xmem(0, 16)).hex(),
        "meta",
        hex(model.read_xmem_metadata(0)),
    )
    print("CRs:", {i: model.read_register("cr", i) for i in range(16)})

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
xt = arrays["x"][:, :channels]
g = arrays["gamma"][:channels][None, :]
b = arrays["beta"][:channels][None, :]
if kind == "rmsnorm":
    want = xt * (1.0 / np.sqrt(np.maximum((xt * xt).mean(1, keepdims=True), eps))) * g
else:
    mu = xt.mean(1, keepdims=True)
    sc = 1.0 / np.sqrt(np.maximum((xt * xt).mean(1, keepdims=True) - mu * mu, eps))
    want = (xt - mu) * sc * g + b


def row_of(name, r, c=0, n=None):
    """Row r * chunks + c of ``name``, decoded from how XMEM holds it."""
    reg = placement.region(name)
    row = reg.base_row + r * chunks + c
    return _decode(row, n if n else min(128, channels - 128 * c))


def sca_row(index, n=128):
    """Bookkeeping row ``index`` of ``sca``, decoded."""
    return _decode(placement.region("sca").base_row + index, n)


def _decode(row, n):
    d = model.read_xmem(row * row_bytes, row_bytes)
    if not plan.format.nx8:
        return np.frombuffer(d, dtype=np.float32)[:n].astype(np.float64)
    from ipu_isa.nx8 import decode_row

    scale, dyn = split_metadata(model.read_xmem_metadata(row * row_bytes))
    return np.asarray(decode_row(d[:128], plan.format.qf, scale, dyn), dtype=np.float64)[:n]


print("status:", model.status, "cycles:", model.stats().cycles)
print("kind", kind, "rows", rows, "channels", channels, "chunks", chunks)
print("rows:", {n: (r.base_row, r.rows) for n, r in placement.regions.items()})
err = np.abs(got - want)
print("max|err| =", err.max(), "bad lanes:", int((err > 0.1).sum()))
for i, nm in enumerate(("means", "squares", "A", "D")):
    rr = placement.region("sca").base_row + i
    sc, dy = split_metadata(model.read_xmem_metadata(rr * row_bytes))
    print(
        f"sca[{i}] {nm:8s} meta scale={sc} dyn={dy} lanes0-7={np.round(sca_row(i, 8), 5)}"
        f" bytes={bytes(model.read_xmem(rr * row_bytes, 8)).hex()}"
    )
for nm in ("invn", "epsr", "maskr"):
    rr = placement.region(nm).base_row
    sc, dy = split_metadata(model.read_xmem_metadata(rr * row_bytes))
    print(f"{nm}: scale={sc} dyn={dy} lane0={_decode(rr, 1)[0]!r}")
print("R_ACC:", np.frombuffer(bytes(model.read_register("r_acc", 0)), dtype=np.float32)[:6])
for r in (ROW, rows // 2, rows - 1):
    xt = row_of("x", r, 0)
    if chunks > 1:
        xt = np.concatenate([row_of("x", r, c) for c in range(chunks)])
    mean = xt.mean()
    var = (xt * xt).mean() - mean * mean
    a = 1.0 / np.sqrt(max(var, eps))
    print(f"row {r}: mean {mean:.5g} var {var:.5g} A(expect) {a:.5g}")
    print("  got    ", np.round(got[r, :6], 4))
    print("  want   ", np.round(want[r, :6], 4))
    print("  err    ", np.round(err[r, :6], 4))
    print(
        "  sca mean",
        np.round(sca_row(0)[r : r + 1], 5),
        "sq",
        np.round(sca_row(1)[r : r + 1], 4),
        "A",
        np.round(sca_row(2)[r : r + 1], 5),
        "D",
        np.round(sca_row(3)[r : r + 1], 5),
    )
    print("  p      ", np.round(row_of("p", r), 4))
    print("  x      ", np.round(xt[:6], 4))
