"""row_norm's reference: per-row normalisation over the channel axis.

``x[r]`` is row r's ``channels`` values as XMEM holds them (the harness hands
float64 tensors of the stored, dequantized values), ``gamma``/``beta`` the
per-channel affine parameters as their rows hold them.

    layernorm  y[r, j] = (x[r, j] - mean_r) * A_r * gamma[j] + beta[j]
    rmsnorm    y[r, j] =  x[r, j]           * A_r * gamma[j]

with the biased mean and variance of the row and

    A_r = rsqrt(max(var_r, eps))        (layernorm)
    A_r = rsqrt(max(mean_j x[r, j] ^ 2, eps))        (rmsnorm)

The floor is what the kernel does -- ACTIVATE.QUANTIZE's rsqrt takes the
maximum of the variance it reduced and the eps row -- so a row of zero (or,
past the packer's zeros, non-existent) variance gets 1/sqrt(eps) and not an
infinity. The harness rounds the result to the variant of the run, row by row,
as the store does.
"""

import numpy as np


def reference(x, gamma, beta, **params):
    """``{"y": ...}`` for the case's ``kind``."""
    rows, channels = params["rows"], params["channels"]
    eps = float(params.get("eps", 0.00001))
    xt = np.asarray(x, dtype=np.float64)[:rows, :channels]
    g = np.asarray(gamma, dtype=np.float64)[:channels]
    if params["kind"] == "rmsnorm":
        scale = 1.0 / np.sqrt(np.maximum(np.mean(xt * xt, axis=1, keepdims=True), eps))
        return {"y": xt * scale * g}
    mean = np.mean(xt, axis=1, keepdims=True)
    var = np.maximum(np.mean(xt * xt, axis=1, keepdims=True) - mean * mean, eps)
    scale = 1.0 / np.sqrt(var)
    b = np.asarray(beta, dtype=np.float64)[:channels]
    return {"y": (xt - mean) * scale * g + b}
