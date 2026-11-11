"""The raw bytes conv2d's regions hold: the weights in the layout the program wants.

The activations (``x``, ``y``) are the chip's layout -- the harness's default,
one entity per ``ceil(F / 128)`` rows of 128 lanes -- and the bias is one row
of ``cout`` values. The *constants* are prepared offline, so the weights are
laid out the way the multiply stage reads them:

    tap-major, channel-minor: row ``t * chunks + c`` holds the ``128`` channels
    of tap ``t = ky * kw + kx`` for channel chunk ``c``, i.e.
    ``W[c, 0, t // kw, t % kw]``.

One word therefore multiplies an input pixel row (128 lanes = 128 channels) by
that tap's weight row lane-wise, which is the depthwise conv's inner loop.

The two ``bytes`` regions are the region's exact bytes, so they are sized in the
row width of the variant of the run (``plan.format.row_bytes``: 512 in FP32).
"""

import numpy as np
from ipu_isa.formats import FORMATS
from ipu_isa.registers import REGISTER_DEFINITIONS

#: Bytes :kbd:`LD.MASK` reads: ``R_MASK``, 8 slots of 16 (one bit per lane).
_MASK_BYTES = REGISTER_DEFINITIONS["r_mask"]["size_bytes"]


def mask_ones(plan):
    """``R_MASK`` with every lane bit of every slot set, as one row's bytes.

    :kbd:`LD.MASK` reads a row's first 128 bytes into ``R_MASK`` in both element
    modes; every lane of every multiply must be active, because the register
    keeps whatever the previous kernel left in it. Whatever fills the rest of an
    FP32 row is never read.
    """
    blob = bytearray(FORMATS[plan.format].row_bytes)
    blob[:_MASK_BYTES] = b"\xff" * _MASK_BYTES
    return bytes(blob)


def zero_row(plan):
    """The value 0 in every lane of the ``zeros`` region, as its exact bytes.

    The out-of-image taps of a window read this row (:kbd:`LD.MULT.CYCLIC` from
    the ``zeros`` region) and must contribute nothing at all, so it has to decode
    to exactly 0.0. The kernel is FP32 (``kernel.toml`` explains why NX8's 16384
    addressable rows cannot hold the widest call), where the element encoding is
    IEEE float32 and 128 zero lanes are 512 zero bytes -- unlike an NX8 row,
    whose byte ``0x00`` is the normal value ``2 ** (scale - 127)``.
    """
    rows = int(plan.derived["dw"])
    return b"\x00" * (rows * FORMATS[plan.format].row_bytes)


class TapMajor:
    """``[cout, cin / groups, kh, kw]`` weights as ``kh * kw * ceil(cout / 128)``
    rows of 128 lanes: row ``t * chunks + c`` is tap ``t``'s weight for channel
    ``c`` (the depthwise case: one filter row per output channel)."""

    def rows(self, shape, plan):
        """``kh * kw`` rows of ``ceil(cout / 128)`` rows each."""
        p = plan.params
        return int(p["kh"]) * int(p["kw"]) * (-(-int(p["cout"]) // 128))

    def to_rows(self, a, plan):
        """The weight tensor as ``(rows, 128)``, lanes past ``cout`` zero."""
        p = plan.params
        cout, kh, kw = int(p["cout"]), int(p["kh"]), int(p["kw"])
        groups = int(p["groups"])
        chunks = -(-cout // 128)
        wt = np.asarray(a, dtype=np.float64).reshape(cout, int(p["cin"]) // groups, kh, kw)
        if wt.shape[1] != 1:
            raise ValueError("tap_major lays out depthwise weights (one filter per channel)")
        flat = wt[:, 0, :, :].reshape(cout, kh * kw)  # (cout, kh * kw), tap-major columns
        out = np.zeros((kh * kw * chunks, 128), dtype=np.float64)
        for t in range(kh * kw):
            for r in range(chunks):
                taken = min(128, cout - 128 * r)
                out[t * chunks + r, :taken] = flat[128 * r : 128 * r + taken, t]
        return out

    def from_rows(self, r, plan, shape):
        """The weight tensor those rows hold (the inverse of :meth:`to_rows`)."""
        p = plan.params
        cout, kh, kw = int(p["cout"]), int(p["kh"]), int(p["kw"])
        chunks = -(-cout // 128)
        grid = np.asarray(r, dtype=np.float64).reshape(kh * kw, chunks, 128)
        flat = np.zeros((kh * kw, cout), dtype=np.float64)
        for row in range(chunks):
            taken = min(128, cout - 128 * row)
            flat[:, 128 * row : 128 * row + taken] = grid[:, row, :taken]
        return np.ascontiguousarray(flat.T).reshape(*shape)


#: The transform ``[inputs.wt]`` names: ``pack = "tap_major"``.
tap_major = TapMajor()
