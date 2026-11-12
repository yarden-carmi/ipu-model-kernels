"""silu: Sign-split exact sigmoid: each branch feeds exp2 a strictly non-positive argument (x*log2e for x<0, -x*log2e for x>=0, log2e applied as split HI/LO constants), then combines x*recip(1+e) on the positive side with x*e*recip(1+e) on the negative side; no |x| and no 1-inv subtraction.

kind: variation
hw: MULT x2 (split log2e), ACC, select by sign, exp2, ACC, RECIP, MULT x2, store per intermediate
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 2.6226043701171875e-06, "mean_abs": 1.227712716211915e-06, "sqnr_db": 123.0927944519947}, "dynamic": {"max_abs": 0.12191295623779297, "mean_abs": 0.014993327614888752, "sqnr_db": 40.05484235898579}}
"""

def fn(x):
    a = store(x * LOG2E_HI, dim=-1)
    a = store(a + x * LOG2E_LO, dim=-1)             # x * log2(e)
    arg = torch.where(x >= 0, -a, a)                # always <= 0 for exp2
    e = store(exp2(arg), dim=-1)                    # e^{-|x|}
    inv = store(reciprocal(1.0 + e), dim=-1)        # 1/(1+e)
    y = torch.where(x >= 0, x * inv, x * e * inv)   # x*sigmoid(x) both sides
    return store(y, dim=-1)
