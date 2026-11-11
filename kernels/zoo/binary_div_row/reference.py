"""binary_div_row's reference: y = a / b with b broadcast as a row.

``a`` is the ``numel`` elements of a as its rows hold them (the harness hands
float64 tensors of the stored, dequantized values), ``b`` the ``inner`` values
of b, and ``y[i] = a[i] / b[i mod inner]`` -- the row-broadcast semantics: b's
values repeat over the rows of a, lane-aligned (``inner`` is a power of two,
so ``(128r + l) mod inner`` factors as a b-row index and a lane).

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(a, b, **params):
    """``{"y": a / tile(b)}`` for the case's ``numel`` and ``inner``."""
    numel = int(params["numel"])
    inner = int(params["inner"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:inner]
    tiled = np.tile(bt, max(1, -(-numel // inner)))[:numel]
    return {"y": at / tiled}
