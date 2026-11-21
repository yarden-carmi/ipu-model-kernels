import torch

def reference(**kw):
    x = kw['in0'].double().reshape(-1, 1)[:kw['s0_tokens']]
    kk = min(kw['s0_vocab'], kw['s1_k'])
    ramp = torch.arange(kw['s0_vocab'], dtype=torch.float64).reshape(1, -1)
    selector = (x == ramp).to(torch.float64)[:, :kk]
    out = selector @ kw['w'].double()[:kk]
    return {'out0': out.reshape(kw['s1_m'], kw['s1_n'])}
