"""quick_gelu: Same quick_gelu but as a 256-entry LUT over a wider [-12, 12] range with linear interpolation and asymptotic tails outside.

kind: approximation
hw: generic LUT with lo/hi tails, no other vector ops
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.0009416707907803357, "mean_abs": 0.00012954605122218846, "sqnr_db": 78.25027704526816}, "dynamic": {"max_abs": 0.121826171875, "mean_abs": 0.012829103276239515, "sqnr_db": 41.57850775495288}}
"""

def fn(x):
    def f(t):
        return t * torch.sigmoid(1.702 * t)
    lo = lambda t: torch.zeros_like(t)
    hi = lambda t: t
    return lut(f, lo, hi, r=12.0, entries=256)(x)
