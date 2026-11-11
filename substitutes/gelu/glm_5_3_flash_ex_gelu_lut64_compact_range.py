"""gelu: GELU computed with a compact 64-entry LUT of the exact function over [-4,4] (where 99.99% of the mass lies) with linear interpolation and constant asymptotic extension outside, trading range for finer resolution at the same hardware cost as a sparse 256-entry table.

kind: approximation
hw: LUT (64 entries over [-4,4]), MULT, ACC, one store.
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.0016071357822511345, "mean_abs": 0.00025654525509297924, "sqnr_db": 73.01179465749543}, "dynamic": {"max_abs": 0.12183380126953125, "mean_abs": 0.012131908584270693, "sqnr_db": 41.79427271364601}}
"""

import torch

def _gelu_lut():
    r = 4.0
    n = 64
    xs = torch.linspace(-r, r, n, dtype=torch.float32)
    table = 0.5 * xs * (1.0 + torch.erf(xs / 1.4142135624))
    return xs, table

_XS, _TBL = _gelu_lut()

def fn(x):
    r = 4.0
    n = 64
    idx_f = (x + r) * ((n - 1) / (2 * r))
    inside = (x >= -r) & (x <= r)
    idx_c = idx_f.clamp(0, n - 1)
    idx0 = idx_c.floor()
    i0 = idx0.to(torch.int64).clamp(0, n - 1)
    i1 = (i0 + 1).clamp(0, n - 1)
    frac = (idx_c - idx0).clamp(0, 1)
    v0 = _TBL[i0]
    v1 = _TBL[i1]
    y_in = v0 + frac * (v1 - v0)
    # outside: gelu(x) -> x for x >> 0, -> 0 for x << 0
    y_out = torch.where(x > 0, x, torch.zeros_like(x))
    y = torch.where(inside, y_in, y_out)
    return store(y)
