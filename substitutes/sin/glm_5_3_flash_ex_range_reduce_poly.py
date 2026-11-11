"""sin: Range-reduce x mod 2π, then evaluate a degree-7 minimax polynomial for sin on [-π/2, π/2] with one store of the reduced argument and one store of the result.

kind: approximation
hw: MULT/ACC (add, multiply, subtract), AGG ops for reduction, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.17848765359940444, "mean_abs": 0.022165069197810222, "sqnr_db": 23.813716076264804}, "dynamic": {"max_abs": 0.1864991745678708, "mean_abs": 0.025215815407040182, "sqnr_db": 23.68665572367474}}
"""

def fn(x):
    TWO_PI = 6.283185307179586
    INV_TWO_PI = 0.15915494309189535
    HALF_PI = 1.5707963267948966
    k = torch.round(x * INV_TWO_PI)
    r = x - k * TWO_PI
    r = store(r, dim=-1)
    r2 = r * r
    # degree-7 minimax poly for sin on [-pi/2, pi/2]
    c1 = -1.6666666666666631e-01
    c2 = 8.33333333332249e-03
    c3 = -1.388888888874e-04
    c4 = 2.4801587289e-06
    p = c4; p = p * r2 + c3
    p = p * r2 + c2
    p = p * r2 + c1
    p = p * r2 + 1.0
    s = r * p
    return store(s, dim=-1)
