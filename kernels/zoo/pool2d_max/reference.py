"""pool2d_max's reference: y = maxpool2d(x), on what XMEM holds.

``x`` is the ``h * w`` pixels of the input as their rows hold them (the
harness hands float64 tensors of the stored, dequantized values), and ``y``
is stored the same way. ``kind`` is only ``max`` here: this kernel is the
max-pooling half of the pool2d primitive.

A tap outside the image (``padding`` > 0) is dropped, which is exactly what a
max over the window's in-image taps computes: the taps that remain are the
same set either way.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(x, **params):
    """``{"y": max over each pixel's k x k window}`` for the case's shape."""
    h = int(params["h"])
    w = int(params["w"])
    k = int(params["k"])
    stride = int(params["stride"])
    padding = int(params["padding"])
    out_h = (h + 2 * padding - k) // stride + 1
    out_w = (w + 2 * padding - k) // stride + 1
    at = np.asarray(x, dtype=np.float64).reshape(h, w, -1)
    y = np.full((out_h, out_w, at.shape[2]), -np.inf, dtype=np.float64)
    for oy in range(out_h):
        for ox in range(out_w):
            y0 = oy * stride - padding
            x0 = ox * stride - padding
            for ky in range(k):
                for kx in range(k):
                    gy, gx = y0 + ky, x0 + kx
                    if 0 <= gy < h and 0 <= gx < w:
                        y[oy, ox] = np.maximum(y[oy, ox], at[gy, gx])
    return {"y": y.reshape(out_h, out_w, -1)}
