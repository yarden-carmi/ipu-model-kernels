"""sigmoid: Restructures exp2_recip to avoid the absolute value by splitting into positive and negative branches with separate exp2 calls and selecting via mask, reducing stores.

kind: variation
hw: MULT, ACC, AaQ exp2 (two calls), torch.where (lane select), store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.000807642936706543, "mean_abs": 0.00047685674201297656, "sqnr_db": 61.123981196525314}, "dynamic": {"max_abs": 0.00780797004699707, "mean_abs": 0.0021208405124615165, "sqnr_db": 47.718983112823175}}
"""

def fn(x):
    # For x >= 0: sigmoid = 1/(1+exp(-x)) = 1/(1+exp2(-x*log2e))
    # For x < 0: sigmoid = exp(x)/(1+exp(x)) = exp2(x*log2e)/(1+exp2(x*log2e))
    z_pos = -x * LOG2E_HI
    z_neg = x * LOG2E_HI
    e_pos = exp2(z_pos)
    e_neg = exp2(z_neg)
    s_pos = reciprocal(1.0 + e_pos)
    s_neg = e_neg * reciprocal(1.0 + e_neg)
    y = torch.where(x >= 0, s_pos, s_neg)
    return store(y)
