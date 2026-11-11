"""sigmoid: Computes sigmoid via the identity sigmoid(x) = 0.5*(1 + tanh(x/2)), approximating tanh with a rational form exp2-based since tanh is unavailable.

kind: variation
hw: MULT, ACC (subtract, add, multiply by constants), AaQ exp2, reciprocal, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.0008076578378677368, "mean_abs": 0.0004768568306725701, "sqnr_db": 61.123980534682914}, "dynamic": {"max_abs": 0.00780797004699707, "mean_abs": 0.0021208405124615165, "sqnr_db": 47.718983112823175}}
"""

def fn(x):
    h = x * 0.5
    # tanh(h) = 1 - 2/(exp(2h)+1); use exp2 with non-positive input
    e = exp2(-torch.abs(h) * (2.0 * LOG2E_HI))
    # for h>0: tanh = 1 - 2e/(1+e)... actually tanh(h) = (1-e)/(1+e) with e=exp(-2|h|)
    t = (1.0 - e) * reciprocal(1.0 + e)
    y = 0.5 * (1.0 + t)
    # fix sign: for x<0, t must be negated
    y = torch.where(x >= 0, y, 1.0 - y)
    return store(y)
