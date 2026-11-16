import torch

def rounded(x):
    x = x.float().double()
    a = x.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0 ** -126)))
    scale = e.max(dim=-1, keepdim=True).values
    step = torch.pow(2.0, torch.maximum(e, scale - 6) - 4)
    y = torch.floor(a / step + 0.5) * step
    return torch.minimum(y, torch.pow(2.0, scale) * (2 - 1 / 16)) * x.sign()

def reference(**kw):
    r, c = kw['s1_rows'], kw['s1_channels']
    x = kw['in0'].permute(2, 1, 0).reshape(-1, c)[:r].contiguous()
    x = x + kw['operand'].reshape(r,c)
    x = rounded(x.reshape(-1,128)).reshape(r,c)
    def norm(x, stage):
        mu = x.mean(-1,keepdim=True)
        var = (x-mu).square().mean(-1,keepdim=True)
        return (x-mu)*torch.rsqrt(var+kw[f's{stage}_eps'])*kw[f'gamma{stage}']+kw[f'beta{stage}']
    y = norm(x,1)
    z = rounded(y.reshape(-1,128)).reshape(kw['s2_rows'],kw['s2_channels'])
    z = norm(z,2)
    return {'out0':y.unsqueeze(0), 'out1':z.unsqueeze(0)}
