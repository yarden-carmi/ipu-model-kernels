"""layout_copy's reference: y = x, on what XMEM holds.

``x`` is the ``numel`` elements as their rows hold them (the harness hands
float64 tensors of the stored, dequantized values), one row per 128 lanes and
lanes past ``numel`` zero, and ``y`` is stored the same way. kind = copy is a
pure data movement.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(x, **params):
    """``{"y": x}`` -- the copy is the identity."""
    numel = int(params["numel"])
    return {"y": np.asarray(x, dtype=np.float64).reshape(-1)[:numel]}
