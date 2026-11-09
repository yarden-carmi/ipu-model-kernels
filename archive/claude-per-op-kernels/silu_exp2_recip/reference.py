import math

import torch


def reference(
    x: torch.Tensor, *, numel: int, log2e_hi: float, log2e_lo: float
) -> dict[str, torch.Tensor]:
    """y = x * sigmoid(x), as the kernel computes it: sigmoid(x) =
    1 / (1 + exp2(-x * c)) with c = log2e_hi + log2e_lo, the kernel's two MULT
    constants (1.442688, log2(e) to 4.9e-6). The kernel's intermediate NX8
    roundings (e, r, x * e) are not modelled: the tolerance covers them. The
    harness rounds y to the variant of the run."""
    c = log2e_hi + log2e_lo
    return {"y": x * torch.sigmoid(x * (c * math.log(2.0)))}  # 2^(-x c) = e^(-x c ln 2)
