import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device)
    hat = (1 - (ids[:, None] - ramp).abs()).clamp_min(0).double()
    a = hat @ kw['w0']
    shifted = (kw['in0'].reshape(-1).double() + kw['in1'].reshape(-1)[0].double().clamp(-64, 64)).to(torch.int64)
    delta = shifted[:, None] - torch.arange(kw['s3_vocab'], device=ids.device)
    b = (1 - delta * delta).clamp_min(0).double() @ kw['w4']
    c = kw['s10_channels']
    aux = kw['aux'].reshape(-1)
    x = a + b + aux[:c].reshape(1, c)
    mean = x.mean(-1, keepdim=True)
    var = ((x - mean) ** 2).mean(-1, keepdim=True)
    y = (x - mean) / torch.sqrt(var + kw['s10_eps'])
    y = y * kw['gamma'].reshape(c) + kw['beta'].reshape(c)
    return {'out0': y.reshape(1, kw['s10_rows'], c)}
