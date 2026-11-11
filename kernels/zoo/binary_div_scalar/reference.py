"""binary_div_scalar's reference: y = a / b with b one scalar, on what XMEM holds.

``a`` is the ``numel`` elements of the dividend as its rows hold them (the
harness hands float64 tensors of the stored, dequantized values), one row per
128 lanes and lanes past ``numel`` zero, and ``y`` is stored the same way.
``b`` is the one scalar of row 0 of its region.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(a, b, **params):
    """``{"y": a / b}`` with the scalar ``b``."""
    numel = int(params["numel"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    scalar = np.asarray(b, dtype=np.float64).reshape(-1)[0]
    return {"y": at / scalar}
