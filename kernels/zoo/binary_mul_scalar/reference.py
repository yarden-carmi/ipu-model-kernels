"""binary_mul_scalar's reference: y = a (op) b[0], on what XMEM holds.

``a`` is the ``numel`` elements of the activation as its rows hold them (the
harness hands float64 tensors of the stored, dequantized values), one row per
128 lanes and lanes past ``numel`` zero, and ``y`` is stored the same way.
``b`` is the one scalar value.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np

#: Each op as the elementwise function of it, over float64, against a scalar.
_OPS = {
    "add": np.add,
    "sub": np.subtract,
    "mul": np.multiply,
    "max": np.maximum,
}


def reference(a, b, **params):
    """``{"y": a (op) b[0]}`` for the case's ``op``."""
    numel = int(params["numel"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    bv = np.asarray(b, dtype=np.float64).reshape(-1)[0]
    return {"y": _OPS[params["op"]](at, bv)}
