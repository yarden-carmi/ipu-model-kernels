"""tanh: Cheaper stand-in: a 16-entry nearest-entry LUT over [-2, 2] with hard ±1 asymptotes outside, trading accuracy for a much smaller table footprint.

kind: estimation
hw: MULT/ACC for index scaling (idx = clamp(round(4x), -8, 8) via add 0.5 + floor via min/max), lut() with 16 entries, store() on the index and result
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.1242628114996478, "mean_abs": 0.04248894092090261, "sqnr_db": 24.335148797272073}, "dynamic": {"max_abs": 0.12813391769304872, "mean_abs": 0.043993879330782804, "sqnr_db": 24.18328480966352}}
"""

def fn(x):
    def lo(t):
        return torch.where(t >= 0, 1.0, -1.0)
    def hi(t):
        return torch.where(t >= 0, 1.0, -1.0)
    idx = x * 4.0
    idx = idx + torch.where(idx >= 0, 0.5, -0.5)  # round via ACC
    idx = torch.clamp(idx, -8.0, 8.0)
    store(idx)
    y = lut(lambda t: torch.tanh(t), lo, hi, r=2.0, entries=16)(idx / 4.0)
    store(y)
    return y
