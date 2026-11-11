"""unary_abs's reference: y = |x| elementwise, on what XMEM holds.

``x`` is the ``numel`` elements of the input as its rows hold them (the harness
hands float64 tensors of the stored, dequantized values), one row per 128 lanes
and lanes past ``numel`` zero, and ``y`` is stored the same way.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on: the kernel's
datapath builds |x| exactly in FP32 (max(-x, x)) and only the store rounds.
"""

import numpy as np


def reference(x, **params):
    """``{"y": |x|}``."""
    numel = int(params["numel"])
    xt = np.asarray(x, dtype=np.float64).reshape(-1)[:numel]
    return {"y": np.abs(xt)}
