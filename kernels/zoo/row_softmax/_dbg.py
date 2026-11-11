"""row_softmax's debug helper: run one case and print its rows against the golden.

    bazel run //kernels/zoo/row_softmax:dbg -- [case] [format] [anything-for-a-dump]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/row_softmax`` are the checks).
"""

import sys
from pathlib import Path

import numpy as np

from ipu_emu.reference import ReferenceModel
from ipu_harness.abi import apply, register_writes
from ipu_harness.assembly import assemble
from ipu_harness.cases import expand, inputs_for
from ipu_harness.manifest import load_manifest
from ipu_harness.packing import pack, stored_rows, unpack
from ipu_harness.params import plan_case
from ipu_harness.placement import place
from ipu_isa.codec.disasm import disassemble

CASE = sys.argv[1] if len(sys.argv) > 1 else "default"
FMT = sys.argv[2] if len(sys.argv) > 2 else "dynamic"
SHOW = len(sys.argv) > 3

manifest = load_manifest(Path("kernels/zoo/row_softmax"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params
rows, n = p["rows"], p["n"]

x = np.asarray(inputs_for(case, plan).tensors["x"])

placement = place(plan, {name: stored_rows(t, plan) for name, t in tensors.items()})
model = ReferenceModel(plan.format.mode)
words = tuple(assemble(plan).words)
model.load_program(words)
row_bytes = plan.format.row_bytes

packed = pack(tensors["x"], x, plan)
base = placement.region("x").base_row * row_bytes
model.write_xmem(base, packed.data)
for index, meta in enumerate(packed.metadata or ()):
    model.write_xmem_metadata(base + index * row_bytes, meta)
print("x: rows=", placement.region("x"), "bytes=", len(packed.data))
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
        model.read_xmem_metadata((region.base_row + i) * row_bytes)
        for i in range(region.rows)
    )
)
got = unpack(tensors["y"], data, plan, meta)

xh = x  # the harness's own input is already the variant's values
shift = np.maximum(xh, 0.0) * 2  # the kernel's own shift, a row constant
num = 2 ** (xh * 1.437500 + xh * 0.00518798828125 - shift)
rinv = 1.0 / num.sum(axis=1, keepdims=True)
want = num * rinv
err = np.abs(got - want)
print("--- y: rows=", (region.base_row, region.rows), "meta0=", None if meta is None else meta[:3])
print("max|err| =", err.max())
if err.size:
    r, cc = np.unravel_index(int(np.argmax(err)), err.shape)
    print(f"worst [{r},{cc}]: got={got[r, cc]:.8g} want={want[r, cc]:.8g} x={np.round(x[r, max(0, cc - 2):cc + 3], 4)}")
    print("  row got sum =", got[r].sum(), "want max =", want[r].max())
    print("  row got ", np.round(got[r, :12], 5))
    print("  row want", np.round(want[r, :12], 5))
    big = np.argsort(-err[r])[:4]
    print("  row's worst lanes:", [(int(j), round(float(err[r, j]), 6)) for j in big])
for i in range(min(rows, 4)):
    for t in range(tiles):
        lo, hi = 128 * t, min(n, 128 * (t + 1))
        ratio = got[i, lo:hi] / np.maximum(want[i, lo:hi], 1e-12)
        print(
            f"row {i} chunk{t}: ratio mean={ratio.mean():.4f} min={ratio.min():.4f}"
            f" max={ratio.max():.4f} mass want={want[i, lo:hi].sum():.4f}"
        )
    print(f"  got  {np.round(got[i, : min(n, 6)][:6], 5)}")
    print(f"  want {np.round(want[i, : min(n, 6)][:6], 5)}")
    print(f"  rowsum got={got[i].sum():.4f} bad_rows={int((err.max(axis=1) > 0.02).sum())}")

print("x[0,:6] =", np.round(x[0, : min(n, 6)], 5))
tiles_ = -(-n // 128)
tail = n % 128 or 128
print("x[:,0] =", np.round(x[:, 0], 5))
print("status:", model.status, "cycles:", model.stats().cycles)
print("R_ACC:", np.frombuffer(model.read_register("r_acc", 0), dtype=np.float32)[:4])
print("R1:", np.frombuffer(model.read_register("r", 1)[:8], dtype=np.float32))
