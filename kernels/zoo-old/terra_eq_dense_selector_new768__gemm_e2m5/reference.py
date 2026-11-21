import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)
    v = int(kw['s0_vocab'])
    selector = (x[:, None] == torch.arange(v, device=x.device)[None, :]).to(torch.float64)
    y = selector @ kw['w'].reshape(int(kw['s1_k']), int(kw['s1_n']))
    return {'out0': y.reshape(1, int(kw['s1_m']), int(kw['s1_n']))}
