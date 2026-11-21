import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    x = torch.where(x == 8191, 8190, x).to(torch.int64)
    j = torch.arange(kw['s2_vocab'], device=x.device)
    selector = (1 - (x[:, None] - j).abs()).clamp_min(0).double()
    first = selector @ kw['w']
    return {'out0': first.unsqueeze(0), 'out1': kw['table'].reshape(1, 1, kw['s5_dim']).expand(1, kw['s5_tokens'], -1).clone()}
