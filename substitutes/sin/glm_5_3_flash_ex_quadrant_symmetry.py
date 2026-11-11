"""sin: Reduce x to [-π/2, π/2] via floor to octants, exploit sin symmetry (sign flips and π−x identity) to evaluate one polynomial, storing the reduced argument and sign mask.

kind: variation
hw: MULT/ACC, comparisons via torch.where, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.2662464380264282, "mean_abs": 0.07226637360837959, "sqnr_db": 16.49693510918307}, "dynamic": {"max_abs": 0.26591092348098755, "mean_abs": 0.07385167843442378, "sqnr_db": 16.51670418378746}}
"""

def fn(x):
    INV_2PI = 0.15915494309189535
    TWO_PI = 6.283185307179586
    k = torch.floor(x * INV_2PI + 0.5)
    r = x - k * TWO_PI
    r = store(r, dim=-1)
    # now r in [-π, π]; reduce to [-π/2, π/2]
    r = torch.where(r > 1.5707963267948966, 3.141592653589793 - r, r)
    r = torch.where(r < -1.5707963267948966, -3.141592653589793 - r, r)
    sign = torch.where((r < 0), -1.0, 1.0)
    a = torch.abs(r)
    a2 = a * a
    # degree-5 poly for sin(a)/a on [0, pi/2]
    p = -2.3889859e-05
    p = p * a2 + 1.9873698e-03
    p = p * a2 + -8.3334581e-02
    p = p * a2 + 1.0
    s = sign * a * p
    return store(s, dim=-1)
