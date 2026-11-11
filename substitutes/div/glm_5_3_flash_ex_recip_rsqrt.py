"""div: Compute the reciprocal via reciprocal of sqrt: b^{-1} = rsqrt(b^2) (sign preserved by re-applying sign(b)), trading a sqrt for a multiply.

kind: variation
hw: MULT (b*b), AaQ rsqrt, MULT (sign restore and a * 1/b), one store for the reciprocal
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 3.814697265625e-06, "mean_abs": 2.0986625770547107e-08, "sqnr_db": 145.347112601768}, "dynamic": {"max_abs": 0.5334014892578125, "mean_abs": 0.03086853487992869, "sqnr_db": 34.4153586470087}}
"""

def fn(a, b):
    s = torch.sign(b)
    r = torch.rsqrt(b * b)
    r = store(r * s, dim=-1)
    return store(a * r, dim=-1)
