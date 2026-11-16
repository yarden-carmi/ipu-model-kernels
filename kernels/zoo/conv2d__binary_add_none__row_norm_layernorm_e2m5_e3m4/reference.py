import torch
import torch.nn.functional as F
def rounded(x):
    r=x.float().reshape(-1,128).double()
    a=r.abs(); e=torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale=e.max(-1,keepdim=True).values
    step=2.0**(torch.maximum(e,scale-2)-5)
    y=torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(x.shape)
def reference(**p):
    h,w=p['s0_h'],p['s0_w']; co=p['s0_cout']
    x=p['in0'][:,0].reshape(1,1,h,w)
    weight=p['weights'].reshape(p['s0_kh'],p['s0_kw'],1,co).permute(3,2,0,1)
    y=F.conv2d(x,weight,p['bias'].flatten() if p['s0_bias'] else None,stride=p['s0_stride']).permute(0,2,3,1).reshape(-1,co)
    y=rounded(y)+p['operand'].reshape(-1,co)
    out=y
    y=rounded(y)
    mu=y.mean(-1,keepdim=True); v=(y-mu).square().mean(-1,keepdim=True)
    z=(y-mu)*torch.rsqrt(v+p['s2_eps'])*p['gamma'].flatten()+p['beta'].flatten()
    return dict(out0=out.reshape(-1,128),out1=z.reshape(-1,128))
