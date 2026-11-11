"""conv2d's reference: y = conv2d(x, W) + b for a depthwise window.

``x`` is the ``h x w`` grid of pixels, each with ``cin`` channels (the layout
XMEM holds: pixel-major rows of 128 lanes), ``w`` is the canonical
``[cout, cin / groups, kh, kw]`` weight tensor and ``bias`` the ``cout``
per-channel constants; ``y`` is the ``out_h * out_w`` grid of output pixels in
the same row layout. The kernel is the depthwise case of the signature, so
``groups == cin`` and ``cout == cin`` (``cin / groups == cout / groups == 1``,
the guards in ``kernel.toml`` refuse anything else) and each output channel
multiplies one input channel's window by its own filter.

Out-of-image taps contribute nothing (zero padding), which is what the kernel
does too: it reads them from a zero row.

The harness rounds the result to the variant of the run, row by row, as the
store does, so this is the exact value the kernel must land on.
"""

import numpy as np


def reference(x, wt, b=None, **params):
    """``{"y": conv2d(x, w) + bias}`` over float64."""
    h, wcin = int(params["h"]), int(params["w"])
    cin, cout = int(params["cin"]), int(params["cout"])
    kh, kw = int(params["kh"]), int(params["kw"])
    stride, padding = int(params["stride"]), int(params["padding"])
    groups = int(params["groups"])
    out_h = (h + 2 * padding - kh) // stride + 1
    out_w = (wcin + 2 * padding - kw) // stride + 1

    xa = np.asarray(x, dtype=np.float64).reshape(h, wcin, cin)
    wa = np.asarray(wt, dtype=np.float64).reshape(cout, cin // groups, kh, kw)
    y = np.zeros((out_h * out_w, cout), dtype=np.float64)
    cpg = cout // groups
    for g in range(groups):
        co = slice(g * cpg, (g + 1) * cpg)
        ci = slice(g * (cin // groups), (g + 1) * (cin // groups))
        for oy in range(out_h):
            for ox in range(out_w):
                acc = np.zeros(cpg, dtype=np.float64)
                for ky in range(kh):
                    iy = oy * stride + ky - padding
                    if iy < 0 or iy >= h:
                        continue
                    for kx in range(kw):
                        ix = ox * stride + kx - padding
                        if ix < 0 or ix >= wcin:
                            continue
                        tap = wa[co, :, ky, kx] * xa[iy, ix, ci]
                        acc += tap.sum(axis=1) if tap.ndim > 1 else tap
                y[oy * out_w + ox, co] = acc
    if b is not None:
        y += np.asarray(b, dtype=np.float64).reshape(1, cout)
    return {"y": y.reshape(out_h, out_w, cout)}
