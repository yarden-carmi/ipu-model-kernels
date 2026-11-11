"""softmax: Uses the split constant LOG2E_HI + LOG2E_LO for a compensated x*log2e product before exp2, improving accuracy of the exponent argument without extra stored stages.

kind: variation
hw: AGG.MAX, MULT, ACC, exp2, AGG.SUM, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 1.2516975402832031e-06, "mean_abs": 5.0771885711106645e-09, "sqnr_db": 118.32181327282505}, "dynamic": {"max_abs": 0.00557398796081543, "mean_abs": 7.802255402644383e-05, "sqnr_db": 42.076401556519514}}
"""

import torch
LOG2E_HI = 1.4284437274975781  # exactly representable
LOG2E_LO = 0.014253313437821958
def fn(x, dim):
    m = torch.amax(x, dim=dim, keepdim=True)
    xs = x - m                       # <= 0, FP32 accumulator
    hi = xs * LOG2E_HI
    lo = xs * LOG2E_LO
    t = hi + lo                      # compensated arg, still in accumulator
    t = torch.clamp(t, max=0.0)
    e = torch.exp2(t)
    s = torch.sum(e, dim=dim, keepdim=True)
    y = e * torch.reciprocal(s)
    return store(y, dim)
