"""layout's reference: y = cat((a, b), dim=0), on what XMEM holds.

``a`` and ``b`` are the ``numel`` elements of the two source regions as their
rows hold them (the harness hands float64 tensors of the stored, dequantized
values), one row per 128 lanes; ``y`` is stored the same way.

A concat takes the leading ``numel/2`` elements of each region -- the rows a
producer that wrote a ``numel/2``-element tensor left at its base -- and puts
them end to end: y's first rows/2 rows are a's, its last rows/2 rows are b's.
A copy is the leading ``numel`` elements of ``a`` alone, row for row, and reads
nothing from ``b``.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(a, b, **params):
    """``{"y": the concatenation of the two sources}`` for the case's ``kind``."""
    numel = int(params["numel"])
    taken = numel if params["kind"] == "copy" else numel // 2
    at = np.asarray(a, dtype=np.float64).reshape(-1)[:taken]
    if params["kind"] == "copy":
        return {"y": at}
    bt = np.asarray(b, dtype=np.float64).reshape(-1)[:taken]
    return {"y": np.concatenate((at, bt))}
