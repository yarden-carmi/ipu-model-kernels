"""The raw bytes layout_copy's scratch regions hold.

A scratch tensor declared with ``bytes`` is written verbatim, which is what the
mask row needs: :kbd:`LD.MASK` reads a row's first 128 bytes into ``R_MASK``,
and every lane of the kernel's multiplies must be active -- the registers keep
what the previous kernel left them.
"""


def mask_ones(plan):
    """``R_MASK`` with all 128 lane bits set, as one NX8 row's bytes."""
    return b"\xff" * 128
