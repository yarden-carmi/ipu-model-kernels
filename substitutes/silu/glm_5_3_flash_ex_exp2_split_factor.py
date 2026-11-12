"""silu: Same exp2+reciprocal dataflow but factored as exp2(-|x|)*exp2(-|x|*(log2e-1)) so the exp2 argument is exactly -|x| (no rounded log2e product inside exp2), and the sign is handled by 1-inv on the negative side instead of the max(x*r, x*e*r) trick.

kind: variation
hw: max (|x|), MULT, exp2 x2, MULT, ACC, RECIP, MULT, store per intermediate
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 2.6226043701171875e-06, "mean_abs": 1.2294043916227793e-06, "sqnr_db": 123.07917539784657}, "dynamic": {"max_abs": 0.1306450366973877, "mean_abs": 0.01979613990721435, "sqnr_db": 37.886936617041314}}
"""

def fn(x):
    ax = store(torch.maximum(x, -x), dim=-1)        # |x|
    d = LOG2E_HI - 1.0 + LOG2E_LO                   # log2(e) - 1, exact scalar
    e1 = store(exp2(-ax), dim=-1)                   # exp2 arg exactly -|x|
    e2 = store(exp2(-ax * d), dim=-1)               # correction factor
    denom = store(1.0 + e1 * e2, dim=-1)            # 1 + e^{-|x| ln2}
    inv = store(reciprocal(denom), dim=-1)          # sigmoid(|x|)
    neg = store(1.0 - inv, dim=-1)                  # sigmoid(-|x|)
    sig = torch.where(x >= 0, inv, neg)
    return store(x * sig, dim=-1)
