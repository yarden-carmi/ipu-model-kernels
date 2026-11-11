"""binary_sub_col's reference: y = a (op) b, broadcast = col.

``a`` is the ``inner`` rows of ``numel / inner`` elements as the rows hold
them (the harness hands float64 tensors of the stored, dequantized values),
``b`` is the ``inner`` values, one per row of a, and ``y`` is stored the same
way: ``y[r][j] = a[r][j] op b[r]``.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np

#: Each op as the elementwise function of it, over float64.
_OPS = {
    "add": np.add,
    "sub": np.subtract,
    "mul": np.multiply,
    "max": np.maximum,
}


def reference(a, b, **params):
    """``{"y": a (op) b}`` with b's value for row r broadcast along it."""
    inner = int(params["inner"])
    at = np.asarray(a, dtype=np.float64).reshape(inner, -1)
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:inner][:, None]
    return {"y": _OPS[params["op"]](at, bt)}
