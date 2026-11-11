"""conv2d_depthwise's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/conv2d_depthwise:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/conv2d_depthwise`` are the checks).
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
FMT = sys.argv[2] if len(sys.argv) > 2 else "fp32"
SHOW = len(sys.argv) > 3

manifest = load_manifest(Path("kernels/zoo/conv2d_depthwise"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
from ipu_harness.cases import inputs_for  # noqa: E402

arrays = dict(inputs_for(case, plan, overrides={}).tensors)

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
    # the goldens see what XMEM holds, as the runner's do
    arrays[name] = unpack(tensors[name], packed.data, plan, packed.metadata)

for name in ("maskr", "zeros"):
    if name in tensors:
        packed = region_fill(tensors[name], plan, placement.region(name).rows)
        print(
            f"  fill {name}: {len(packed.data)} bytes {packed.data[:4].hex()} meta {packed.metadata}"
        )
        base = placement.region(name).base_row * row_bytes
        model.write_xmem(base, packed.data)
        for index, meta in enumerate(packed.metadata or ()):
            model.write_xmem_metadata(base + index * row_bytes, meta)

apply(model, tuple(register_writes(plan, placement)))

print("derived:", dict(plan.derived))
print("CR:", {i: model.read_register("cr", i) for i in range(16)})
print("rows:", {name: (r.base_row, r.rows) for name, r in placement.regions.items()})


def compact(word, pc):
    """One line: the word's non-NOP instructions."""
    parts = []
    for line in disassemble(word).splitlines():
        text = line.strip()
        if not text or text.startswith("NOP") or text == f"{pc:3d}":
            continue
        parts.append(text)
    return f"{pc:3d} " + " | ".join(parts)


if SHOW:
    want_pcs = (
        set(range(36, 42))
        | set(range(55, 63))
        | set(range(78, 86))
        | set(range(100, 108))
        | set(range(120, 128))
        | set(range(143, 152))
    )
    with open("/tmp/conv_dump.txt", "w", encoding="utf-8") as handle:
        for pc, word in enumerate(words):
            handle.write(f"  {pc:3d} {disassemble(word)}\n")
    for pc, word in enumerate(words):
        if pc in want_pcs:
            print(compact(word, pc))

records = []
for _ in range(200000):
    rec = model.step()
    records.append(rec)
    if rec.outcome != "retired":
        break
if SHOW:
    ybase = placement.region("y").base_row
    yrows = placement.region("y").rows
    seen = []
    for rec in records:
        for xw in rec.xmem_writes:
            row = xw.address // row_bytes
            if ybase <= row < ybase + yrows:
                seen.append((rec.cycle, rec.pc_before, row - ybase))
    print("stores:", len(seen))
    for s in seen[:60]:
        print("   ", s)
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
print("R_ACC:", np.frombuffer(model.read_register("r_acc", 0), dtype=np.float32)[:4])
print("R0:", bytes(model.read_register("r", 0)[:8]).hex())
print("R1:", bytes(model.read_register("r", 1)[:8]).hex())
print("R_CYCLIC:", bytes(model.read_register("r_cyclic", 0)[:8]).hex())
print("R_MASK:", bytes(model.read_register("r_mask", 0)[:8]).hex())
print("max|err| =", np.abs(np.asarray(got).reshape(-1) - want.reshape(-1)).max())
for name in ("x", "wt", "b"):
    if name in arrays:
        again = unpack(
            tensors[name],
            model.read_xmem(
                placement.region(name).base_row * row_bytes, placement.region(name).rows * row_bytes
            ),
            plan,
            None
            if not plan.format.nx8
            else tuple(
                model.read_xmem_metadata((placement.region(name).base_row + i) * row_bytes)
                for i in range(placement.region(name).rows)
            ),
        )
        d = np.abs(np.asarray(again) - np.asarray(arrays[name])).max()
        print(f"  region {name} changed by {d}")
n = int(np.prod(plan.shapes["y"]))
rows = -(-n // 128)
g = np.asarray(got).reshape(-1)
out_h, out_w, cout = plan.shapes["y"]
ctiles = -(-cout // 128)
G = np.asarray(got).reshape(out_h, out_w, cout)
W = want.reshape(out_h, out_w, cout)
for oy in range(min(out_h, 10)):
    e = np.abs(G[oy] - W[oy]).max(axis=1)
    print(f"  oy {oy}: bad ox {list(np.nonzero(e > 0.06)[0])} maxes {np.round(e, 3).tolist()}")
for i in range(min(rows, 4)):
    lo, hi = i * 128, min(n, (i + 1) * 128)
    err = np.abs(g[lo:hi] - want.reshape(-1)[lo:hi])
    bad = np.nonzero(err > 0.02)[0]
    print(
        f"  row {i}: lanes {lo}..{hi - 1} max|err|={err.max():g} bad={len(bad)} at {bad[:12] + lo}"
    )
GP = np.asarray(got).reshape(out_h * out_w, cout)
WP = want.reshape(out_h * out_w, cout)
for nm in ("zeros", "maskr"):
    reg = placement.region(nm)
    print(
        f"  {nm}: bytes {bytes(model.read_xmem(reg.base_row * row_bytes, 8)).hex()}"
        f" meta {hex(model.read_xmem_metadata(reg.base_row * row_bytes))}"
    )
yr = placement.region("y")
for q in (0, 1, 6, 12, 24):
    print(
        f"  y pixel {q} ({q // out_w},{q % out_w}) bytes:",
        bytes(model.read_xmem((yr.base_row + q) * row_bytes, 8)).hex(),
        "meta",
        hex(model.read_xmem_metadata((yr.base_row + q) * row_bytes)),
    )
for q in (0, 1, 4):
    print(
        f"  x pixel {q} bytes:",
        bytes(model.read_xmem(placement.region("x").base_row * row_bytes + q * row_bytes, 8)).hex(),
        "meta",
        hex(model.read_xmem_metadata(placement.region("x").base_row * row_bytes + q * row_bytes)),
    )
print("  want p0:", np.round(WP[0][:6], 6), "got p0:", np.round(GP[0][:6], 6))
print("  want p1:", np.round(WP[1][:6], 6), "got p1:", np.round(GP[1][:6], 6))
print("  want p6:", np.round(WP[6][:6], 6), "got p6:", np.round(GP[6][:6], 6))
print("  x[0]:", np.round(np.asarray(arrays["x"]).reshape(-1, int(p["cin"]))[0][:6], 6))
print("  wt:", np.round(np.asarray(arrays["wt"]).reshape(-1)[:12], 6))
if SHOW:
    # where did each pixel's correct value land? (a y-pointer drift shows up here)
    D = np.abs(GP[:, None, :] - WP[None, :, :]).max(axis=2)
    for q in range(D.shape[1]):
        order = np.argsort(D[:, q])[:2]
        print(
            f"  want q={q} ({q // out_w},{q % out_w}): got at "
            f"{[(int(o), o // out_w, o % out_w, round(float(D[o, q]), 3)) for o in order]}"
        )
