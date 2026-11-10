"""unary's reference: y = fn(x), elementwise, on what XMEM holds.

``x`` is the ``numel`` values of the input as its rows hold them (the harness
hands over float64 tensors of the stored, dequantized values), one row per 128
lanes and lanes past ``numel`` zero; ``y`` is stored the same way, so this
kernel's output row is the next kernel's input row.

The kernel realises the two sigmoid-shaped functions with the AaQ ``exp2`` of
``-|z| log2 e`` and the AaQ ``reciprocal`` of ``1 + e``,

    e = 2 ** (-|z| log2 e) = exp(-|z|),   q = 1 / (1 + e),   w = e q

for z the value whose sigmoid multiplies x -- ``x`` itself for silu and
quick_gelu, and ``1.5957691216057308 (x + 0.044715 x^3)`` for gelu_tanh, which
is always of x's sign -- and then joins the two signed branches with one
``ACC.MAX``:

    y = max(x q, x w)

For ``x >= 0`` ``q = sigmoid(x) >= 1/2 >= w``, so the larger product is ``x q``;
for ``x < 0`` both products are negative and the smaller magnitude, ``x w =
x e/(1+e) = x sigmoid(x)``, wins. So the kernel computes the exact value below,
with four 8-bit NX8 row round-trips (``|z|``, ``e``, ``q``, ``w``) in front of
the output store, and the harness rounds this golden to the case's variant row
by row exactly as the store quantizes.
"""

import numpy as np


def _sigmoid(x):
    """1 / (1 + exp(-x)), computed stably for both signs."""
    out = np.empty_like(x)
    pos = x >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-x[pos]))
    ex = np.exp(x[~pos])
    out[~pos] = ex / (1.0 + ex)
    return out


#: The fns whose value is x * sigmoid(x) (silu, quick_gelu) or x * sigmoid(ca +
#: ck x^3) (gelu_tanh): one dataflow, the sigmoid's argument differing.
_SIGMOIDIC = ("silu", "quick_gelu", "gelu_tanh")

_GELU_C = 1.5957691216057308  # 2 sqrt(2 / pi)
_GELU_K = 0.044715


def reference(x, **params):
    """``{"y": fn(x)}`` for the case's ``fn``, over what XMEM holds."""
    fn = params["fn"]
    numel = int(params["numel"])
    xt = np.asarray(x, dtype=np.float64).reshape(-1)
    n = min(numel, xt.size)
    v = xt[:n]
    if fn in _SIGMOIDIC:
        z = v if fn != "gelu_tanh" else _GELU_C * (v + _GELU_K * v * v * v)
        y = v * _sigmoid(z)
    elif fn == "relu":
        y = np.maximum(v, 0.0)
    elif fn == "relu6":
        y = np.clip(v, 0.0, 6.0)
    elif fn == "neg":
        y = -v
    else:  # pragma: no cover - kernel.toml's choices gate this
        raise ValueError(f"unary has no {fn!r}")
    out = np.zeros_like(xt)
    out[:n] = y
    return {"y": out.reshape(np.shape(x))}
