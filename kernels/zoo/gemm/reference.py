"""gemm's reference: y = a @ w (+ b), on what XMEM holds.

``a[i]`` is token i's k elements. ``w`` is *input-major*: ``w[t]`` holds the
n+1 weights of input channel t (row k is padding: the last prefetch of a tile
reads it and no multiply uses it; column n pads the last 128-lane tile), so the
kernel's word for input t multiplies that row by the scalar ``a[i][t]`` and
accumulates it into the 128 slots of the tile. ``b[0]`` is the n biases.

The harness hands these as float64 tensors of what XMEM holds and rounds the
result to the case's variant (NX8: quantized row by row, as the store does), so
this is the exact value the kernel must land on.
"""


def reference(a, w, b=None, **params):
    """``y[i, j] = sum_t a[i, t] * w[t, j] (+ b[j])``."""
    m, k, n = params["m"], params["k"], params["n"]
    y = a[:m, :k] @ w[:k, :n]
    if params.get("bias"):
        y = y + b[:, :n]
    return {"y": y}
