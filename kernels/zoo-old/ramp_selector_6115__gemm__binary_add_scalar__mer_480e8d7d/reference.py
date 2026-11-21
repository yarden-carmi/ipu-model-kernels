import torch

def rounded(x):
    a = x.float().double().abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 2) - 5)
    y = torch.floor(a / step + 0.5) * step
    return torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 32)) * x.sign()

def reference(**kw):
    x = kw['in0'].reshape(-1, 1)
    # Equality selects at most one vocabulary row; avoid a huge dense selector.
    first = torch.zeros((kw['s0_tokens'], kw['s1_n']), dtype=torch.float64, device=x.device)
    ids0 = x.flatten()
    valid = (ids0 == ids0.floor()) & (ids0 >= 0) & (ids0 < kw['s0_vocab'])
    first[valid] = kw['w1'][ids0[valid].long()]
    stored0 = rounded(first.reshape(-1,128)).reshape_as(first)
    ids = stored0.flatten()[:kw['s2_numel']] + kw['in1'].flatten()[0]
    ids = ids - (ids == 492).to(ids.dtype)
    sel = (ids[:,None] == torch.arange(kw['s4_vocab'],device=x.device)).double()
    second = sel @ kw['w5']
    stored1 = rounded(second.reshape(-1,128)).reshape_as(second)
    selected = stored1[:,3*(kw['s6_sel']//3):3*(kw['s6_sel']//3)+1]
    indicator = (selected == 0).double()
    return {'out0':first.unsqueeze(0), 'out1':second.unsqueeze(0), 'out2':(indicator @ kw['w8']).unsqueeze(0)}
