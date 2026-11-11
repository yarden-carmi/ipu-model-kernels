"""gelu: Computes the tanh-form GELU where tanh(z) is replaced by a degree-5 polynomial/rational hybrid approximation evaluated with only MULT/ACC ops, avoiding any store for the tanh sub-result.

kind: approximation
hw: MULT/ACC vector arithmetic, exp2 for the rational part, one final store of the output.
proposed by: GLM-5.3-Flash-EXL3
op error: {"fp32": {"max_abs": 0.021741390228271484, "mean_abs": 0.006697996505823127, "sqnr_db": 46.18630592390634}, "dynamic": {"max_abs": 0.12183380126953125, "mean_abs": 0.014515912644318266, "sqnr_db": 40.47455375608464}}
"""

def fn(x):
    import torch
    # tanh(z) ≈ z * (27 + z*z) / (27 + 9*z*z) for |z| small, clamped to ±1 outside
    # GELU: 0.5*x*(1+tanh(c*(x+0.044715x^3))), c=sqrt(2/pi)
    c = 0.7978845608028654
    x2 = x * x
    inner = c * (x + 0.044715 * x * x2)
    z = torch.clamp(inner, -3.0, 3.0)
    z2 = z * z
    num = 27.0 + z2
    den = 27.0 + 9.0 * z2
    # den > 0 always; reciprocal via rsqrt: den = rsqrt(1/den)^-1 -> use rsqrt twice
    inv_den = rsqrt(rsqrt(den) * rsqrt(den))  # 1/den via two rsqrt (approx)
    # Actually rsqrt(t)=1/sqrt(t); 1/den = rsqrt(den*den) = rsqrt(den)^2
    inv_den = rsqrt(den) * rsqrt(den)
    tanh_approx = z * num * inv_den
    # for |inner|>3, tanh saturates to sign(inner)*1
    sign = torch.where(inner >= 0, torch.tensor(1.0), torch.tensor(-1.0))
    tanh_full = torch.where(inner.abs() > 3.0, sign, tanh_approx)
    y = 0.5 * x * (1.0 + tanh_full)
    return store(y)

# note: rsqrt is the AaQ hardware function; den*den not needed since rsqrt(den)^2 = 1/den
