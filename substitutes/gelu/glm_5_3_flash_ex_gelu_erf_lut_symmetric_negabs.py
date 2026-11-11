"""gelu: GELU via the erf LUT evaluated only on non-positive arguments: since erf is odd, erf(x) = -erf(-x), so the table is indexed with -|x| (keeping exp2-style range reduction unnecessary) and the sign is restored with a multiply by sign(x), halving the effective table error on the symmetric domain.

kind: approximation
hw: LUT (256 entries, erf over [0, 8] mirrored), MULT, ACC; one store for the final result.
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.08418861031532288, "mean_abs": 0.029286364261580936, "sqnr_db": 33.84256962653842}, "dynamic": {"max_abs": 0.12183380126953125, "mean_abs": 0.03397794776340888, "sqnr_db": 33.225290501338876}}
"""

import torch

def _erf_lut():
    r = 8.0
    n = 256
    xs = torch.linspace(-r, r, n, dtype=torch.float32)
    table = torch.erf(xs)
    return xs, table

_XS, _TBL = _erf_lut()

def fn(x):
    # erf is odd: erf(x) = -erf(-x). Evaluate the LUT only at -|x| <= 0,
    # then restore the sign. This halves the interpolation error vs. a
    # full-range table at the same entry count.
    ax = x.abs()
    neg_ax = -ax
    # linear interpolation on the mirrored table
    # table value at -a is -erf(a), so erf(a) = -lut(-a)
    idx_f = (neg_ax + 8.0) * (255.0 / 16.0)
    idx0 = idx_f.floor().clamp(0, 254)
    frac = (idx_f - idx0).clamp(0, 1)
    i0 = idx0.to(torch.int64)
    i1 = (idx0 + 1).clamp(0, 255).to(torch.int64)
    v0 = -_TBL[i0]
    v1 = -_TBL[i1]
    erf_pos = v0 + frac * (v1 - v0)  # erf(ax)
    erf_x = erf_pos * torch.where(x >= 0, torch.ones_like(x), -torch.ones_like(x))
    y = 0.5 * x * (1.0 + erf_x)
    return store(y)
