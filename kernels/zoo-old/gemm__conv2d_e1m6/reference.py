import torch
import torch.nn.functional as F

def rounded(x):
    r = x.float().reshape(-1,128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1,keepdim=True).values
    step = 2.0 ** (torch.maximum(e, scale) - 6)
    y = torch.floor(a / step + 0.5) * step
    y = torch.minimum(y, 2.0**scale * (2 - 1/64))
    return (y*r.sign()).reshape(x.shape)

def reference(**p):
    h,w,c = p['s1_h'],p['s1_w'],p['s0_n']
    wf = p['w0'].reshape(c,2,128)
    a = p['in0'][:,:p['s0_k']] @ wf[:,1,:p['s0_k']].T
    if p['s0_bias']: a = a + wf[:,0,0]
    out = torch.zeros(c,h,128,dtype=torch.float64)
    out[:,:,:w] = a.T.reshape(c,h,w)
    x = rounded(out)[:,:,:w].unsqueeze(0)
    wt = p['w1'][1:,:p['s1_cout']].reshape(p['s1_cin'],p['s1_kh'],p['s1_kw'],p['s1_cout']).permute(3,0,1,2)
    b = p['w1'][0,:p['s1_cout']] if p['s1_bias'] else None
    y = F.conv2d(x,wt,b,stride=p['s1_stride'],padding=p['s1_padding'],groups=p['s1_groups'])
    dst = torch.zeros(y.shape[2]*y.shape[3],128,dtype=torch.float64)
    dst[:,:p['s1_cout']] = y[0].flatten(1).T
    return {'out0':out.reshape(-1,128),'out1':dst}
