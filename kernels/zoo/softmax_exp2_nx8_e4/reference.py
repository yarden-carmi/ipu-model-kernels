import math

import torch


def reference(
    x: torch.Tensor,
    *,
    dim_last: bool,
    n: int,
    rows: int,
    log2e_hi: float,
    log2e_lo: float,
) -> dict[str, torch.Tensor]:
    """y = softmax(x) along the last axis, as the kernel computes it:
    2^(c (x - max x)) / SUM 2^(c (x - max x)) with c = log2e_hi + log2e_lo, the
    kernel's two MULT constants (log2(e) to 4.9e-6), so y = softmax(x c ln 2).
    The kernel's intermediate NX8 roundings (the numerators and 1 / sum) are
    not modelled: the tolerance covers them. The harness rounds y to the
    variant of the run."""
    c = log2e_hi + log2e_lo
    z = x.double() * (c * math.log(2.0))
    return {"y": torch.softmax(z, dim=-1).to(torch.float32)}
