"""binary_add_row's reference: y = a (op) b with b broadcast as a row.

``a`` is the ``numel`` elements of the activation as its rows hold them (the
harness hands float64 tensors of the stored, dequantized values), one row per
128 lanes and lanes past ``numel`` zero, and ``y`` is stored the same way.
``b`` holds ``inner`` values and repeats over a's rows: ``y[i] = a[i] op
b[i mod inner]`` -- a bias of ``inner`` features added to every group of
``inner`` elements of a. Since ``inner`` is a multiple of 128, the repetition
is row-aligned: a's row r uses b's row ``r mod ceil(inner/128)``.

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
    """``{"y": a (op) b[i mod inner]}`` for the case's ``op``."""
    numel = int(params["numel"])
    inner = int(params["inner"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:inner]
    tiled = np.tile(bt, numel // inner + 1)[:numel]
    return {"y": _OPS[params["op"]](at, tiled)}
