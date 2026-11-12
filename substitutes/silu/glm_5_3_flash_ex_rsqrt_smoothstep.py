"""silu: Replaces the exponential sigmoid with the smooth step x/sqrt(x^2+4): silu(x) ~ 0.5x + 0.5x^2*rsqrt(x^2+4), correct 0.5x+x^2/4 small-x expansion and x / ->0 asymptotes, no exp2 or reciprocal at all.

kind: estimation
hw: MULT, ACC, RSQRT, MULT, ACC, store per intermediate
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.1454634666442871, "mean_abs": 0.06486889795069423, "sqnr_db": 27.580889703288403}, "dynamic": {"max_abs": 0.3044242858886719, "mean_abs": 0.07085748659494845, "sqnr_db": 27.34513516495096}}
"""

def fn(x):
    x2 = store(x * x, dim=-1)                       # x^2
    d = store(x2 + 4.0, dim=-1)                     # x^2 + C (C tuned)
    r = store(rsqrt(d), dim=-1)                     # 1/sqrt(x^2 + 4)
    return store(0.5 * x + 0.5 * x2 * r, dim=-1)    # 0.5x (1 + x/sqrt(x^2+4))
