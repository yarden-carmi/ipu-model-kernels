"""softmax: Reorders the exp2 recipe so the only stores are the shifted exponentials (once, in run precision) and the final output, while max, sum, and reciprocal stay in the FP32 accumulator — fewer NX8 roundings than the per-stage NX8 variants.

kind: variation
hw: AGG.MAX, ACC, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 7.152557373046875e-07, "mean_abs": 4.1631508769520997e-10, "sqnr_db": 133.11548404577326}, "dynamic": {"max_abs": 0.013223111629486084, "mean_abs": 0.00010790579824934518, "sqnr_db": 37.19623299738033}}
"""

import torch
def fn(x, dim):
    m = torch.amax(x, dim=dim, keepdim=True)          # AGG.MAX, no store
    t = (x - m) * 1.4426950408889634                  # ACC chain
    t = torch.clamp(t, max=0.0)
    e = store(torch.exp2(t), dim)                     # single store in run precision (NX8 if quantized)
    s = torch.sum(e, dim=dim, keepdim=True)           # AGG.SUM on stored e
    inv = torch.reciprocal(s)                         # reciprocal
    y = store(e * inv, dim)                           # final store
    return y
