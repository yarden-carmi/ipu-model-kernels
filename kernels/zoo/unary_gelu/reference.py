"""unary_gelu's reference: y = gelu(x), elementwise, on what XMEM holds.

``x`` is the ``numel`` values of the input as its rows hold them (the harness
hands over float64 tensors of the stored, dequantized values), one row per 128
lanes and lanes past ``numel`` zero; ``y`` is stored the same way, so this
kernel's output row is the next kernel's input row.

The kernel computes the tanh form of GELU, x * sigmoid(z) with
z = c (x + 0.044715 x^3) and c = 2 sqrt(2/pi), through the AaQ ``exp2`` of
``-|z| log2 e`` and the AaQ ``reciprocal`` of ``1 + e``:

    e = 2 ** (-|z| log2 e) = exp(-|z|),   q = 1 / (1 + e),   w = e q

and then joins the two signed branches with one ``ACC.MAX``:

    y = max(x q, x w)

For ``x >= 0`` ``q = sigmoid(z) >= 1/2 >= w``, so the larger product is ``x q``;
for ``x < 0`` both products are negative and the smaller magnitude, ``x w =
x e/(1+e) = x sigmoid(z)``, wins.

The program's constants are the dyadic sums below (each part an exact NX8 MULT
constant), so this file evaluates exactly what the datapath computes -- the
tanh form, whose deviation from the erf form is at most ~3.4e-4 absolute, which
is what ``kind = "estimation"`` records. The harness rounds this golden to the
case's variant row by row exactly as the store quantizes.
"""

import numpy as np

#: -log2(e) * c and -log2(e) * c * 0.044715, each as the sum of two dyadic
#: parts of at most 7 significant bits (an NX8 MULT constant's precision).
_LC1 = -2.3125
_LC2 = 0.01025390625
_LD1 = -0.1015625
_LD2 = -0.00140380859375

_LC = _LC1 + _LC2  # -2.30224609375 = -log2(e) * 2 sqrt(2/pi) + 3.8e-5
_LD = _LD1 + _LD2  # -0.10296630859375 = -log2(e) * 2 sqrt(2/pi) * 0.044715 + 2.3e-5


def reference(x, **params):
    """``{"y": gelu(x)}`` over what XMEM holds."""
    numel = int(params["numel"])
    xt = np.asarray(x, dtype=np.float64).reshape(-1)
    n = min(numel, xt.size)
    v = xt[:n]
    a = np.abs(v)
    arg = a * (_LC + _LD * a * a)  # <= 0 in every lane: the exp2 argument
    e = np.exp2(arg)
    q = 1.0 / (1.0 + e)
    w = e * q
    y = np.maximum(v * q, v * w)
    out = np.zeros_like(xt)
    out[:n] = y
    return {"y": out.reshape(np.shape(x))}
