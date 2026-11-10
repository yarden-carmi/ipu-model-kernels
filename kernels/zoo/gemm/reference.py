"""gemm's reference: y = a @ w^T (+ b), on what XMEM holds.

``a[i]`` is token i's k elements, ``w[j]`` output channel j's k weights (w's
row n is padding: the j loop's last prefetch reads it and no multiply uses it),
and ``b[0]`` the n biases. The harness hands these as float64 tensors and rounds
the result to the case's variant (NX8: quantized row by row, as the store
does), so this is the exact value the kernel must land on.
"""


def reference(a, w, b=None, **params):
    """``y[i, j] = sum_k a[i, k] * w[j, k] (+ b[j])``."""
    m, k, n = params["m"], params["k"], params["n"]
    y = a[:m, :k] @ w[:n, :k].T
    if params.get("bias"):
        y = y + b[:, :n]
    return {"y": y}
