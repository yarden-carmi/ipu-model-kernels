import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    return torch.minimum(torch.floor(a / step + 0.5) * step,
                         torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()

def store(x):
    return rounded(x.reshape(-1,128)).reshape_as(x)

def reference(**kw):
    ids = kw['in0'].flatten().long()
    first = torch.zeros((kw['s0_tokens'],kw['s1_n']),dtype=torch.float64)
    valid = (ids >= 0) & (ids < kw['s0_vocab'])
    first[valid] = kw['w1'][ids[valid]]
    first = store(first)
    p = first.flatten()[:kw['s2_numel']] + kw['in1'].flatten()[0]
    p = torch.where(p == 494,p-1,p).long()
    second = torch.zeros((kw['s4_tokens'],kw['s5_n']),dtype=torch.float64)
    valid = (p >= 0) & (p < kw['s4_vocab'])
    second[valid] = kw['w5'][p[valid]]
    second = store(second)
    # pair_floor_mux feeds only the IDs of an unconditional single-row fanout.
    n = kw['s10_channels']
    table = kw['table'].reshape(1,-1).expand(kw['s7_tokens'],-1)
    x = store(store(first + second) + table)
    mu = x.mean(-1,keepdim=True)
    var = ((x-mu)**2).mean(-1,keepdim=True)
    y = (x-mu)/torch.sqrt(var+kw['s10_eps'])
    return {'out0':(y*kw['gamma']+kw['beta']).unsqueeze(0)}
