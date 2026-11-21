import torch
import torch.nn.functional as F

def reference(**kw):
    x = kw['in0']
    c = kw['s0_channels']
    v = x[..., :c]
    y = torch.zeros_like(x)
    y[..., :c] = v * torch.rsqrt((v*v).mean(-1, keepdim=True) + kw['eps']) * kw['gamma'][:c]
    ci, co = kw['s1_cin'], kw['s1_cout']
    a = kw['in1'][..., :ci].permute(0,3,1,2).contiguous()
    w = kw['weights'].reshape(co,-1)[:, :ci].reshape(co,ci,1,1)
    z = F.conv2d(a,w,stride=kw['s1_stride'])
    out = torch.zeros((1,co,z.shape[2],128),dtype=x.dtype)
    out[..., :z.shape[3]] = z
    return {'out0': y, 'out1': out}
