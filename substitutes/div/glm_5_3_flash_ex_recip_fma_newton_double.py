"""div: Division restructured as two Newton-Raphson refinements starting from a cheap rsqrt-based seed: r = rsqrt(b^2) seed, then two FMA-form refinements r = r*(2 - b*r), all in MULT/ACC with stores between refinements.

kind: variation
hw: rsqrt + MULT/ACC (FMA) + store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 3.814697265625e-06, "mean_abs": 2.0986625770547107e-08, "sqnr_db": 145.347112601768}, "dynamic": {"max_abs": 16.033401489257812, "mean_abs": 0.07065634936306253, "sqnr_db": 13.497229844699392}}
"""

def fn(a, b):
    sb = torch.where(b >= 0, 1.0, -1.0)
    ab = torch.abs(b)
    ab = torch.clamp(ab, 1e-30, 1e30)
    ab2 = ab * ab
    ab2 = store(ab2)
    r = torch.rsqrt(ab2)
    r = store(r)
    # Newton-Raphson refinement 1: r = r*(2 - b*r)
    t = b * r
    t = store(t)
    t = 2.0 - t
    t = store(t)
    r = r * t
    r = store(r)
    # Newton-Raphson refinement 2
    t = b * r
    t = store(t)
    t = 2.0 - t
    t = store(t)
    r = r * t
    r = store(r)
    return a * r * sb

