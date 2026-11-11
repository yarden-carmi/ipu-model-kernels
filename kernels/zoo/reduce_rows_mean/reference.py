"""reduce_rows' reference: one reduced value per row of a (rows, n) matrix.

``x`` is the ``rows * n`` values as the rows hold them (the harness hands
float64 tensors of the stored, dequantized values): entity r in
``ceil(n / 128)`` consecutive rows, lanes past ``n`` zero. Only the ``n``
values of a row are reduced -- a lane past ``n`` is padding, not data, and the
kernel's AGG never names it.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(x, kind, rows, n, **params):
    """``{"y": [reduce(x[r, :n]) for r in range(rows)]}``, one column."""
    values = np.asarray(x, dtype=np.float64).reshape(int(rows), int(n))[:, : int(n)]
    k = int(n)
    if kind == "max":
        out = values.max(axis=1)
    else:
        total = values.sum(axis=1)
        out = total / k if kind == "mean" else total
    return {"y": out.reshape(int(rows), 1)}
