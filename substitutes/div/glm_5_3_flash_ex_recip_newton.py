"""div: One Newton-Raphson refinement of a coarse reciprocal seed: r1 = reciprocal(coarse seed) refined as r = r1*(2 - b*r1) using only MULT/ACC and a single reciprocal() seed, giving near-exact division with 3 stores.

kind: approximation
hw: AaQ reciprocal (seed), MULT/ACC for the Newton step, stores for seed, refined reciprocal, and result
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 3.814697265625e-06, "mean_abs": 2.0986625770547107e-08, "sqnr_db": 145.347112601768}, "dynamic": {"max_abs": 0.5334014892578125, "mean_abs": 0.030864684399503517, "sqnr_db": 34.410812027130234}}
"""

def fn(a, b):
    # seed: hardware reciprocal of b (already ~1 ulp; refine once for robustness
    # against NX8 store rounding of a cheaper seed)
    r1 = store(reciprocal(b), dim=-1)
    # Newton step: r = r1 * (2 - b*r1)
    br = b * r1
    r = r1 * (2.0 - br)
    r = store(r, dim=-1)
    return store(a * r, dim=-1)
