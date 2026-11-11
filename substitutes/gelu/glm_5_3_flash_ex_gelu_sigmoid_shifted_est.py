"""gelu: A cheaper stand-in: GELU estimated as x * sigmoid(1.4142x) (sigmoid with a steeper slope closer to the true erf curve than QuickGELU's 1.702 in the mid-range), computed via exp2 + reciprocal with a single final store.

kind: estimation
hw: MULT, ACC, exp2 (AaQ, non-positive argument), reciprocal (AaQ), one store.
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.06655609607696533, "mean_abs": 0.03132809962216624, "sqnr_db": 34.551612903899205}, "dynamic": {"max_abs": 0.12183380126953125, "mean_abs": 0.0344212360225443, "sqnr_db": 33.80032649221911}}
"""

import torch

def fn(x):
    # sigmoid(k x) = 1/(1+exp(-k x)); exp2 arg must be <= 0
    # work with -|k x| and min/max branch selection
    k = 1.4142135624
    kx = k * x
    neg_abs_kx = -kx.abs()
    # exp2(-|kx| * log2e) = exp(-|kx|)
    e = exp2(neg_abs_kx * 1.4426950409)
    # sigmoid(|kx|) = 1/(1+e); for x<0, sigmoid = e/(1+e)
    inv = reciprocal(1.0 + e)
    sig_pos = inv
    sig_neg = e * inv
    sig = torch.where(x >= 0, sig_pos, sig_neg)
    y = x * sig
    return store(y)
