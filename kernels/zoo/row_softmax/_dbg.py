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
from ipu_harness.packing import pack, held, stored_rows, unpack
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

arrays = {k: np.asarray(v) for k, v in inputs_for(case, plan).tensors.items()}
x = arrays["x"]

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
    print(f"{name}: rows={placement.region(name)} bytes={len(packed.data)}")
apply(model, tuple(register_writes(plan, placement)))

print("derived:", dict(plan.derived))
print("CR:", {i: model.read_register("cr", i) for i in range(16)})
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})
if SHOW:
    for pc, word in enumerate(words):
        print(f"  {pc:3d} {disassemble(word)}")

try:
    model.run(5_000_000)
    failed = None
except Exception as error:  # noqa: BLE001 - a debug tool prints the fault
    failed = error

for name in ("y",):
    region = placement.region(name)
    data = model.read_xmem(region.base_row * row_bytes, region.rows * row_bytes)
    meta = (
        None
        if not plan.format.nx8
        else tuple(
            model.read_xmem_metadata((region.base_row + i) * row_bytes)
            for i in range(region.rows)
        )
    )
    print(f"--- {name}: rows={(region.base_row, region.rows)} meta0={None if meta is None else meta[:3]}")
    got = unpack(tensors[name], data, plan, meta)
    if name == "y":
        xh = held(tensors["x"], x, plan)  # what XMEM holds: the golden's input
        want = np.exp(xh - xh.max(axis=1, keepdims=True))
        want = want / want.sum(axis=1, keepdims=True)
        err = np.abs(got - want)
        print("max|err| =", err.max())
        if err.size:
            r, cc = np.unravel_index(int(np.argmax(err)), err.shape)
            print(
                f"worst [{r},{cc}]: got={got[r, cc]:.8g} want={want[r, cc]:.8g} "
                f"x={np.round(x[r, max(0, cc - 2):cc + 3], 4)}"
            )
            print("  row got sum =", got[r].sum(), "want max =", want[r].max())
            print("  row got ", np.round(got[r, :12], 5))
            print("  row want", np.round(want[r, :12], 5))
            big = np.argsort(-err[r])[:4]
            print("  row's worst lanes:", [(int(j), round(float(err[r, j]), 6)) for j in big])
        for i in range(min(rows, 4)):
            r0 = got[i, : min(n, 128)] / np.maximum(want[i, : min(n, 128)], 1e-12)
            r1 = (
                got[i, 128:n] / np.maximum(want[i, 128:n], 1e-12)
                if n > 128
                else np.array([])
            )
            print(
                f"row {i}: chunk0 ratio mean={r0.mean():.4f} min={r0.min():.4f} max={r0.max():.4f} |"
                f" chunk1 ratio mean={r1.mean() if len(r1) else 0:.4f}"
                f" min={r1.min() if len(r1) else 0:.4f} max={r1.max() if len(r1) else 0:.4f}"
                f" | mass want c0={want[i, :128].sum():.4f} c1={want[i, 128:].sum():.4f}"
            )
            print(f"row {i} got ", np.round(got[i, : min(n, 6)], 4))
            print(f"row {i} want", np.round(want[i, : min(n, 6)], 4))
            print(f"  rowsum got={got[i].sum():.4f} bad_rows="
                  f"{int((err.max(axis=1) > 0.02).sum())}")
    elif name == "y":
        pass
    else:
        print("rows:", region.base_row, region.rows)

print("x[0,:6] =", np.round(x[0, : min(n, 6)], 5))
tiles = -(-n // 128)
tail = n % 128 or 128
if tail < 128:
    from ipu_harness._codec import decode_rows  # noqa: PLC0415

    grid = decode_rows(data, plan.format, meta)
    print(
        f"lanes past n in each entity's last chunk row: max|value| =",
        np.abs(grid[tiles - 1 :: tiles, tail:]).max(),
    )
print("x[:,0] =", np.round(x[:, 0], 5))
print("status:", model.status, "cycles:", model.stats().cycles)
print("R_ACC:", np.frombuffer(model.read_register("r_acc", 0), dtype=np.float32)[:4])
print("R1:", np.frombuffer(model.read_register("r", 1)[:8], dtype=np.float32))
if failed is not None:
    print("FAILED:", failed)
