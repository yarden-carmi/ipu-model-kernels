"""unary_cos's debug helper: run one case and print its rows against the reference.

    bazel run //kernels/zoo/unary_cos:dbg -- [case] [format]

Not a test: it prints, it does not assert (the case x format runs of
``bazel test //kernels/zoo/unary_cos`` are the checks).
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

manifest = load_manifest(Path("kernels/zoo/unary_cos"))
case = next(c for c in expand(manifest) if c.name == CASE)
plan = plan_case(manifest, case.values, FMT, case=case.decl)
tensors = plan.manifest.tensors
p = plan.params

rng = np.random.default_rng(0)
arrays = {"x": rng.uniform(-np.pi / 2, np.pi / 2, plan.shapes["x"])}

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
if True:
    import numpy as _np2
    m2 = ReferenceModel(plan.format.mode)
    m2.load_program(words)
    row_bytes2 = row_bytes
    for name, values in arrays.items():
        packed = pack(tensors[name], values, plan)
        base = placement.region(name).base_row * row_bytes2
        m2.write_xmem(base, packed.data)
        for index, meta in enumerate(packed.metadata or ()):
            m2.write_xmem_metadata(base + index * row_bytes2, meta)
    for name in ("maskr",):
        packed = region_fill(tensors[name], plan, placement.region(name).rows)
        base = placement.region(name).base_row * row_bytes2
        m2.write_xmem(base, packed.data)
        for index, meta in enumerate(packed.metadata or ()):
            m2.write_xmem_metadata(base + index * row_bytes2, meta)
    apply(m2, tuple(register_writes(plan, placement)))
    def raw(reg, idx, n=8):
        return bytes(m2.read_register(reg, idx)[:n]).hex()
    def f32acc():
        return _np2.frombuffer(bytes(m2.read_register("r_acc", 0)[:16]), dtype=_np2.float32)
    for w in range(24):
        rec = m2.step()
        if w in (3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 20, 21):
            print(
                f"w{w}: R0={raw('r',0)} rm={raw('r_meta',0,2)} R1={raw('r',1)}"
                f" cm={m2.read_register('r_cyclic_meta',1)}"
                f" ACC={f32acc()}"
            )
        if m2.status.state.value != "running":
            break
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

import numpy as _np
_B = [26.0/1048576, -91.0/65536, 85.0/2048, -0.5, 1.0]
_xs = arrays["x"].reshape(-1)[:128]
_s = _xs*_xs
_stages = [_B[0]*_s + _B[1], (_B[0]*_s+_B[1])*_s+_B[2], ((_B[0]*_s+_B[1])*_s+_B[2])*_s+_B[3], (((_B[0]*_s+_B[1])*_s+_B[2])*_s+_B[3])*_s+_B[4]]
print("STAGE0 want[0:4]:", np.round(_stages[0][:4], 6))
print("STAGE1 want[0:4]:", np.round(_stages[1][:4], 6))
print("STAGE2 want[0:4]:", np.round(_stages[2][:4], 6))
print("STAGE3 want[0:4]:", np.round(_stages[3][:4], 6))

sreg = placement.region("s")
sdata = model.read_xmem(sreg.base_row * row_bytes, sreg.rows * row_bytes)
smeta = tuple(model.read_xmem_metadata((sreg.base_row + i) * row_bytes) for i in range(sreg.rows))
got_s = unpack(tensors["s"], sdata, plan, smeta)
xs = arrays["x"].reshape(-1)
print("s[0:6] got:", np.round(np.asarray(got_s).reshape(-1)[:6], 4), "want:", np.round(xs[:6] ** 2, 4))
odata = model.read_xmem(placement.region("one").base_row * row_bytes, row_bytes)
print("one[0:4]:", np.frombuffer(odata[:16], dtype=np.float32))
print("status:", model.status, "cycles:", model.stats().cycles)
print("R0[0:4]:", np.frombuffer(bytes(model.read_register("r", 0)[:16]), dtype=np.float32))
print("R1[0:4]:", np.frombuffer(bytes(model.read_register("r", 1)[:16]), dtype=np.float32))
print("CYC slot0[0:4]:", np.frombuffer(bytes(model.read_register("r_cyclic", 0)[:16]), dtype=np.float32))
print("R_ACC[0:4]:", np.frombuffer(bytes(model.read_register("r_acc", 0)[:16]), dtype=np.float32))
yreg = placement.region("y")
ydata = model.read_xmem(yreg.base_row * row_bytes, yreg.rows * row_bytes)
ymeta = tuple(
    model.read_xmem_metadata((yreg.base_row + i) * row_bytes) for i in range(yreg.rows)
)
print("y meta:", [hex(m) for m in ymeta], "bytes:", ydata[:16].hex())
og = np.asarray(unpack(tensors["y"], ydata, plan, ymeta)).reshape(-1)
print("y[0:6] got:", np.round(og[:6], 4))
one_d = placement.region("one")
one_data = model.read_xmem(one_d.base_row * row_bytes, row_bytes)
one_meta = model.read_xmem_metadata(one_d.base_row * row_bytes)
print("one meta:", hex(one_meta), "bytes:", one_data[:16].hex())
print("one unpack:", np.round(np.asarray(unpack(tensors["one"], one_data, plan, (one_meta,))).reshape(-1)[:4], 4))
g = np.asarray(got).reshape(-1)
w = np.asarray(want).reshape(-1)
for i in range(0, 128, 8):
    print(i, np.round(g[i : i + 8], 3), np.round(w[i : i + 8], 3))
g = np.asarray(got).reshape(-1)
if len(g) > 128:
    i = 128
    xv = arrays["x"].reshape(-1)[i]
    sv = xv * xv
    st = [26.0/1048576*sv + -91.0/65536,
          (26.0/1048576*sv + -91.0/65536)*sv + 85.0/2048,
          ((26.0/1048576*sv + -91.0/65536)*sv + 85.0/2048)*sv + -0.5,
          (((26.0/1048576*sv + -91.0/65536)*sv + 85.0/2048)*sv + -0.5)*sv + 1.0]
    print(f"TAIL x={xv!r} s={sv!r} stages={np.round(st,8)} got={g[i]!r}")
    print("s row1 lane0 got:", np.asarray(got_s).reshape(-1)[128], "want:", sv)
print("row 0 got ", np.round(g[:6], 4))
print("row 0 want", np.round(want.reshape(-1)[:6], 4))
print("vs np.cos:", np.abs(np.asarray(got).reshape(-1) - np.cos(arrays["x"].reshape(-1))[: len(g)]).max())
