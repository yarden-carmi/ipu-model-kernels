"""binary's reference: y = a (op) b elementwise, on what XMEM holds.

``a`` and ``b`` are the ``numel`` elements of the two operands as their rows
hold them (the harness hands float64 tensors of the stored, dequantized
values), one row per 128 lanes and lanes past ``numel`` zero, and ``y`` is
stored the same way. Nothing is broadcast: ``broadcast`` is "none" and
``inner`` 0, so ``b`` has ``numel`` values like ``a``.

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
    """``{"y": a (op) b}`` for the case's ``op``."""
    numel = int(params["numel"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:numel]
    return {"y": _OPS[params["op"]](at, bt)}
