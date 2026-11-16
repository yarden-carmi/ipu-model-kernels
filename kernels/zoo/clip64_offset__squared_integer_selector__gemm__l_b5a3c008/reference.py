import torch

def rounded(x):
    shape=x.shape
    r=x.reshape(-1,128).double()
    a=r.abs()
    e=torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale=e.max(-1,keepdim=True).values
    step=2.0**(torch.maximum(e,scale-2)-5)
    return (torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))*r.sign()).reshape(shape)

def reference(**kw):
    x = rounded(kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0].clamp(-64,64))
    ids = x.long()
    ramp = torch.arange(kw['s1_vocab'], device=x.device)
    selector = (1-(ids[:,None]-ramp)**2).clamp_min(0).double()
    first = selector @ kw['w']
    second = torch.ones((kw['s4_tokens'],kw['s4_vocab']),dtype=torch.float64) @ kw['v']
    return {'out0':first.unsqueeze(0),'out1':second.unsqueeze(0)}
