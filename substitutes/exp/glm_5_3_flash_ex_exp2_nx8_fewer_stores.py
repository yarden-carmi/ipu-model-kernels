"""exp: Exact exp2 math restructured to a single accumulator chain and only one store at the end, reducing NX8 rounding stages versus the known two-store variant.

kind: variation
hw: MULT (LOG2E_HI*x, chained in accumulator with LOG2E_LO*x correction), ACTIVATE.QUANTIZE exp2, single store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 13.421875, "mean_abs": 0.0036167606967699786, "sqnr_db": 84.88667579054018}, "dynamic": {"max_abs": 855.96875, "mean_abs": 2.9290038666615303, "sqnr_db": 42.35282101444003}}
"""

def fn(x):
    # chain both LOG2E parts in the FP32 accumulator before any memory write
    t = x * LOG2E_HI
    t = t + x * LOG2E_LO # still in accumulator, no store
    y = exp2(t)
    return store(y)
