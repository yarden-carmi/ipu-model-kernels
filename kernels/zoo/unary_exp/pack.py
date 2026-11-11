"""The raw bytes unary_exp's scratch regions hold.

A scratch tensor declared with ``bytes`` is written verbatim, which is what the
mask row needs: :kbd:`LD.MASK` reads a row's first 128 bytes into ``R_MASK``, and
every lane of the kernel's multiplies must be active -- the registers keep what
the previous kernel left them.
"""


def mask_ones(plan):
    """``R_MASK`` with all 128 lane bits set, in the variant of the plan.

    An NX8 row is 128 bytes, an FP32 row 512: the row bytes of the variant,
    every lane bit set."""
    return b"\xff" * plan.format.row_bytes
