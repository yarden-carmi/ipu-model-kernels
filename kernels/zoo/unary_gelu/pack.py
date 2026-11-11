"""The raw bytes unary_gelu's scratch regions hold.

A scratch tensor declared with ``bytes`` is written verbatim, which is what the
mask row needs: :kbd:`LD.MASK` reads a row's first 128 bytes into ``R_MASK``, and
every lane of every multiply must be active -- the registers keep what the
previous kernel left them, and a lane the mask had off would carry that
kernel's value into the accumulator instead of this kernel's product.
"""


def mask_ones(plan):
    """``R_MASK`` with all 128 lane bits set, as one NX8 row's bytes."""
    return b"\xff" * 128
