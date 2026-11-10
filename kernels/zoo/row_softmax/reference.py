"""row_softmax's reference: a softmax over each row of x.

``y[r, :] = exp(x[r, :]) / sum(exp(x[r, :]))``. The kernel realises the
exponentials with the AaQ ``exp2`` activation (exp2(x * log2(e)); the log2(e)
factor enters as the sum of two exactly representable dyadic terms, one
MULT.RC.VE each, so every product is exact in the FP32 accumulator) and
normalises with the AaQ ``reciprocal`` of the row's sum. Before the exponential
it subtracts a shift common to the row, 2 * max(x, 0) (the max comes out of
AGG.MAX and through an NX8 ``relu`` store, which floors it at 0 so a row of
all-negative logits shifts by nothing and the argument stays <= 0); a
row-common shift cancels in the normalisation, so the golden is the plain
softmax. The harness rounds this golden to the case's NX8 variant row by row,
exactly as the kernel's stores quantize their rows, and the values are what
XMEM holds (the input's own NX8 rounding is the harness's).
"""

import torch


def reference(x, **params):
    """``y[r, :] = softmax(x[r, :])``."""
    return {"y": torch.softmax(x, dim=-1)}
