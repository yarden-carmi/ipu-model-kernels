"""The raw bytes binary_div_row's scratch regions hold, and b's tiled layout.

A scratch tensor declared with ``bytes`` is written verbatim, which is what the
mask row needs: :kbd:`LD.MASK` reads a row's first 128 bytes into ``R_MASK``,
and every lane of the kernel's multiplies must be active -- the registers keep
what the previous kernel left them.

``tiled`` is b's pack transform: b's ``inner`` values laid over whole 128-lane
rows, row ``j`` lane ``l`` holding ``b[(128j + l) mod inner]`` -- exactly the
lane the row-broadcast semantics names, so the kernel reads no rotated or
shuffled row and needs no shuffle on the chip.
"""

import numpy as np

from ipu_harness.packing import LANES


class tiled:
    """``b`` as whole tiled rows: row j lane l is ``b[(128j + l) mod inner]``."""

    @staticmethod
    def rows(shape):
        """``ceil(inner / 128)`` rows."""
        return max(1, -(-shape[-1] // LANES))

    @staticmethod
    def to_rows(a, plan):
        """``a`` tiled over ``(ceil(inner/128), 128)``; every lane filled."""
        inner = a.shape[-1]
        rows = max(1, -(-inner // LANES))
        index = (LANES * np.arange(rows)[:, None] + np.arange(LANES)[None, :]) % inner
        return np.asarray(a, dtype=np.float64).reshape(-1)[index]

    @staticmethod
    def from_rows(r, plan, shape):
        """The ``inner`` values ``r`` holds: ``b[t]`` is row ``t // 128``, lane ``t % 128``."""
        return np.asarray(r, dtype=np.float64).reshape(-1)[: shape[-1]]


def mask_ones(plan):
    """``R_MASK`` with all 128 lane bits set, as one NX8 row's bytes."""
    return b"\xff" * 128
