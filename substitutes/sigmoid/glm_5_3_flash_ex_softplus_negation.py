"""sigmoid: Estimates sigmoid as the derivative of softplus computed via exp2-based softplus with linear tail, one shared exp2.

kind: estimation
hw: MULT, ACC, AaQ exp2, reciprocal, min/max, store
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.000807642936706543, "mean_abs": 0.00047685648371648126, "sqnr_db": 61.1239831949361}, "dynamic": {"max_abs": 0.00780797004699707, "mean_abs": 0.0021208405124615165, "sqnr_db": 47.718983112823175}}
"""

def fn(x):
    # softplus(x) ≈ max(x,0) + log1p(exp(-|x|)); sigmoid = d/dx softplus
    # sigmoid ≈ 1/(1+exp2(-x*log2e)) but computed via softplus piecewise derivative
    ax = torch.abs(x)
    e = exp2(-ax * LOG2E_HI)
    # derivative of softplus = exp(x)/(1+exp(x)) for the smooth part, sign(x) for linear part
    smooth = e * reciprocal(1.0 + e)
    y = torch.where(x >= 0, 1.0 - smooth * 0.0 + smooth, smooth)
    # For x>=0: derivative = 1/(1+e) = smooth... wait smooth = e/(1+e) with e=exp(-|x|)
    # x>=0: sigmoid = 1/(1+exp(-x)) = 1/(1+e) = 1-smooth
    # x<0: sigmoid = exp(x)/(1+exp(x)) = e/(1+e) = smooth (since e=exp(x) when x<0)
    y = torch.where(x >= 0, 1.0 - smooth, smooth)
    return store(y)
