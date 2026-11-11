"""row_norm's reference: per-row RMSNorm over the channel axis.

``x[r]`` is row r's ``channels`` values as XMEM holds them (the harness hands
float64 tensors of the stored, dequantized values), ``gamma`` the per-channel
affine parameter as its rows hold them.

    rmsnorm  y[r, j] = x[r, j] * A_r * gamma[j]

with

    A_r = 1 / sqrt(max(mean_j x[r, j] ^ 2, eps))

The floor is what the kernel does -- ACTIVATE.QUANTIZE's rsqrt takes the
maximum of the mean of squares it reduced and the eps row -- so a row of zero
(or, past the packer's zeros, non-existent) mean of squares gets 1/sqrt(eps)
and not an infinity. The harness rounds the result to the variant of the run,
row by row, as the store does.
"""

import numpy as np


def reference(x, gamma, **params):
    """``{"y": x * rsqrt(mean(x^2) floored at eps) * gamma}`` per row."""
    rows, channels = params["rows"], params["channels"]
    eps = float(params.get("eps", 0.00001))
    xt = np.asarray(x, dtype=np.float64)[:rows, :channels]
    g = np.asarray(gamma, dtype=np.float64)[:channels]
    scale = 1.0 / np.sqrt(np.maximum(np.mean(xt * xt, axis=1, keepdims=True), eps))
    return {"y": xt * scale * g}
