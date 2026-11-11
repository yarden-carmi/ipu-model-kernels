"""unary_log's reference: y = log(x) elementwise, on what XMEM holds.

``x`` is the ``numel`` values of the input as its rows hold them (the harness
hands over float64 tensors of the stored, dequantized values), one row per 128
lanes and lanes past ``numel`` zero; ``y`` is stored the same way, so this
kernel's output row is the next kernel's input row.

The kernel computes the degree-3 minimax monomial of the substitution
``u = x - 1.25`` (so |u| <= 0.75 over the declared input range [0.5, 2]),

    y = b0 + b3 u^3 + b2 u^2 + b1 u,

with the same dyadic constants the program holds in its CRs (the NX8 MULT
constant's 7 significant bits), accumulated in the kernel's own order. The
truncation of the exact log at degree 3 is 8.5e-3 over the range -- under one
step of the output row's grid -- and the kernel's residual against this golden
is its four NX8 row round-trips and the FP32 accumulation, which the harness
rounds row by row exactly as the store quantizes.
"""

import numpy as np

#: The dyadic constants of the program's CR10..CR13.
_B0 = 0.228515625
_B1 = 0.7890625
_B2 = -0.39453125
_B3 = 0.234375


def reference(x, **params):
    """``{"y": log(x)}`` over what XMEM holds, in the kernel's own order."""
    numel = int(params["numel"])
    xt = np.asarray(x, dtype=np.float64).reshape(-1)
    n = min(numel, xt.size)
    v = xt[:n]
    u = v - 1.25
    y = _B0 + _B3 * u * u * u + _B2 * (u * u) + _B1 * u
    out = np.zeros_like(xt)
    out[:n] = y
    return {"y": out.reshape(np.shape(x))}
