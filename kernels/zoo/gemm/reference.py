"""gemm's reference: y = act(a @ w (+ b)), on what XMEM holds.

``a[i]`` is token i's k elements. ``w`` is *input-major*: ``w[t]`` holds the
n weights of input channel t (row k is padding: the last prefetch of a tile
reads it and no multiply uses it; lanes past n are the packer's zeros), so the
kernel's word for input t multiplies that row by the scalar ``a[i][t]`` and
accumulates it into the 128 slots of the tile. ``b[tt]`` is the tile's biases.

The harness hands these as float64 tensors of what XMEM holds and rounds the
result to the case's variant (NX8: quantized row by row, as the store does), so
this is the exact value the kernel must land on. ``relu`` is the AaQ's own and
exact on both sides of 0, so the fused store sees the same value the golden's
quantization does.
"""

import numpy as np


def reference(a, w, b=None, **params):
    """``{"y": act(a @ w (+ b))}`` for the case's ``act``."""
    m, k, n = params["m"], params["k"], params["n"]
    y = a[:m, :k] @ w[:k, :n]
    if params.get("bias"):
        y = y + np.asarray(b, dtype=np.float64).reshape(-1)[:n]
    act = params.get("act", "none")
    if act == "relu":
        y = np.maximum(y, 0.0)
    elif act != "none":  # pragma: no cover - kernel.toml's choices gate this
        raise ValueError(f"gemm has no {act!r}")
    return {"y": y}
