import torch

def reference(**kw):
    x = kw['in0'].to(torch.float64).flatten()[:kw['s0_tokens']]
    ramp = torch.arange(kw['s0_vocab'], dtype=torch.float64, device=x.device)
    sel = (x[:, None] == ramp[None, :]).to(torch.float64)
    out = sel @ (2 * kw['w'].to(torch.float64).reshape(kw['s0_vocab'], kw['s1_n']))
    return {'out0': out.reshape(1, kw['s1_m'], kw['s1_n'])}
