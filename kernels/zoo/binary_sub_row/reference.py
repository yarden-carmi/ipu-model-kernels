"""binary_sub_row's reference: y = a (op) b with b broadcast as a row.

``a`` is the ``numel`` elements of a as its rows hold them (one row per 128
lanes, lanes past ``numel`` zero). ``b`` is the ``inner`` values of the one
broadcast row, lanes past ``inner`` zero: every row of a combines with that
same row, so the broadcast row is padded to 128 lanes and tiled over
``ceil(numel/128)`` rows.

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
    """``{"y": a (op) b}`` with b's row padded and tiled over a's rows."""
    numel = int(params["numel"])
    inner = int(params["inner"])
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:numel]
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:inner]
    row = np.zeros(128, dtype=np.float64)
    row[:inner] = bt
    bt_full = np.tile(row, -(-numel // 128))[:numel]
    return {"y": _OPS[params["op"]](at, bt_full)}
