import torch
def reference(**kw):
    x=kw['in0'].reshape(-1,1).float()
    labels=torch.arange(kw['s0_vocab'],device=x.device,dtype=torch.float32)
    y=(1-(x-labels).abs()).clamp_min(0).double() @ kw['w']
    y=y*torch.rsqrt(y.square().mean(dim=1,keepdim=True)+kw['s2_eps'])*kw['gamma']
    return {'out0':y.reshape(1,kw['s2_rows'],kw['s2_channels'])}
