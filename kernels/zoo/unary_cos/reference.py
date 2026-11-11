"""unary_cos's reference: the degree-8 polynomial the kernel runs, with its
round trips.

``x`` is the ``numel`` elements of the input as its rows hold them (the harness
hands float64 tensors of the stored, dequantized values), one row per 128 lanes
and lanes past ``numel`` zero, and ``y`` is stored the same way.

The kernel evaluates the degree-8 Taylor polynomial of cos with dyadic
coefficients (7 significant bits each, the MULT constant's width) by Horner
from b8 down to b0, and every multiplicand is an NX8 row: s = x*x is stored
and read back once, and every Horner step's p is stored and read back. This
computes the same thing in float64: the FP32 product and accumulate of each
step and the NX8 round trip of every row the kernel stores (s and the four p
rows), quantized with the case's dynamic format against each row's own active
lanes, exactly as the store does. The harness rounds the result once more, row
by row, as the output store does, so this is the value the kernel must land on.
"""

import numpy as np
from ipu_isa.nx8 import Nx8Format, decode_row, encode_row, split_metadata

#: The case's QF half: the ``dynamic`` variant's element type.
_FMT = Nx8Format(sign=1, exp_format=0, num_bits=8, dynamic=True)

#: The Horner chain's constants after b8 (which seeds the accumulator).
_TAIL = ("b6", "b4", "b2")


def _quant(values, active):
    """One row through the store: quantize to NX8 (``active`` lanes) and read
    it back, as the kernel's every multiplicand travels."""
    enc = encode_row([float(v) for v in values], _FMT, active)
    scale, dyn = split_metadata(enc.metadata)
    return np.asarray(decode_row(enc.elements, _FMT, scale, dyn), dtype=np.float32)


def reference(x, **params):
    """``{"y": cos(x)}`` as the kernel's degree-8 dyadic polynomial, with its
    NX8 round trips."""
    numel = int(params["numel"])
    xs = np.asarray(x, dtype=np.float64).reshape(-1)[:numel]
    rows = (numel + 127) // 128
    out = np.empty(numel, dtype=np.float64)
    for r in range(rows):
        lo = r * 128
        n = min(128, numel - lo)
        row = np.zeros(128, dtype=np.float32)
        row[:n] = xs[lo : lo + n].astype(np.float32)
        active = [i < n for i in range(128)]
        # s = x * x: one MULT.RC.VS of the cyclic window, one round trip.
        s = _quant(row * row, active)
        # Horner: p = p * s + bk, the product and the constant one FP32
        # accumulate each, p back through XMEM after every step.
        acc = np.full(128, np.float32(params["b8"]), dtype=np.float32)
        for name in _TAIL:
            acc = s * acc  # MULT.RC.VV, ACC.ADD.FIRST
            acc = acc + np.float32(params[name])  # MULT.EE off the ones row, ACC.ADD
            acc = _quant(acc, active)
        acc = s * acc
        acc = acc + np.float32(params["b0"])
        out[lo : lo + n] = acc[:n]
    return {"y": out}
