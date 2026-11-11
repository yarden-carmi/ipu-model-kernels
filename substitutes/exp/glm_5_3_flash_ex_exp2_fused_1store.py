"""exp: Same exp2 math but fused to a single store by chaining LOG2E_HI*x in the accumulator before memory write.

kind: variation
hw: MULT (LOG2E_HI*x, LOG2E_LO*x, ACC add), ACTIVATE exp2, reciprocal, select
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 13.421875, "mean_abs": 0.003616509235910982, "sqnr_db": 84.88608352526015}, "dynamic": {"max_abs": 28170.34375, "mean_abs": 6.523760936313208, "sqnr_db": 20.41201266246196}}
"""

def fn(x):
    hi = store(LOG2E_HI * x)
    t = hi + LOG2E_LO * x
    tn = -t.abs()
    e = torch.exp2(tn)
    return torch.where(t >= 0, reciprocal(e), e)
