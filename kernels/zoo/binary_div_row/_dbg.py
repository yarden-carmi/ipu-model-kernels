"""binary_div_row's debug helper: run one case and print its rows.

    bazel run //kernels/zoo/binary_div_row:dbg -- [case] [format] [dump]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/binary_div_row`` are the checks).
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

manifest = load_manifest(Path("kernels/zoo/binary_div_row"))
case = next(c for c in expand(manifest) if c.name == CASE)
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

for name in ("maskr", "twos"):
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


def _region_vals(name):
    r = placement.region(name)
    n = r.rows
    d = model.read_xmem(r.base_row * row_bytes, n * row_bytes)
    m = (
        None
        if not plan.format.nx8
        else tuple(model.read_xmem_metadata((r.base_row + i) * row_bytes) for i in range(n))
    )
    return np.asarray(unpack(tensors[name], d, plan, m), dtype=np.float64).reshape(-1), [
        hex(model.read_xmem_metadata((r.base_row + i) * row_bytes)) for i in range(r.rows)
    ]


print("status:", model.status, "cycles:", model.stats().cycles)

for name in ("b", "rcp", "u", "e"):
    if name in placement.regions:
        v, meta = _region_vals(name)
        print(
            name,
            np.round(v[:8], 5),
            "...",
            np.round(v[-4:], 5),
            "meta:",
            meta,
        )

print("max|err| =", np.abs(np.asarray(got).reshape(-1) - want.reshape(-1)).max())
n = int(p["numel"])
g = np.asarray(got).reshape(-1)
w = want.reshape(-1)
av = np.asarray(arrays["a"], dtype=np.float64).reshape(-1)[:n]
bv = np.asarray(arrays["b"], dtype=np.float64).reshape(-1)[: int(p["inner"])]
bt = np.tile(bv, max(1, -(-n // len(bv))))[:n]
rcpv = np.tile(_region_vals("rcp")[0], max(1, -(-n // 128)))[:n]
uv = np.tile(_region_vals("u")[0], max(1, -(-n // 128)))[:n]
ev = np.tile(_region_vals("e")[0], max(1, -(-n // 128)))[:n]
err = np.abs(g - w)
worst = np.argsort(err)[-6:][::-1]
for i in worst:
    j = i % 128
    print(
        f"  lane {i}: got {g[i]:g} want {w[i]:g} err {err[i]:g} rel {err[i] / max(abs(w[i]), 1e-9):g}"
        f" a={av[i]:g} b={bt[i]:g} rcp={rcpv[i]:g} (1/b={1 / bt[i]:.5f})"
        f" u={uv[i]:g} e={ev[i]:g} (want s={1 / bt[i]:.5f})"
    )
for i in range(min(rows := -(-n // 128), 4)):
    lo, hi = i * 128, min(n, (i + 1) * 128)
    err = np.abs(g[lo:hi] - w[lo:hi])
    print(f"  row {i}: lanes {lo}..{hi - 1} max|err|={err.max():g} bad={(err > 0.02).sum()}")
print("row 0 got ", np.round(g[:6], 4))
print("row 0 want", np.round(w[:6], 4))
