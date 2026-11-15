import torch
def reference(**kw):
    w = kw['channels']
    c = kw['rows'] // w
    x = kw['in0'][:, :w]
    y = x * torch.rsqrt(x.square().mean(-1, keepdim=True) + kw['eps']) * kw['gamma'][:w]
    y = torch.where(y > 0, y, 0.0)
    out = torch.zeros(w,w,((c+127)//128)*128,dtype=x.dtype)
    out[:,:,:c] = y.reshape(c,w,w).permute(1,2,0)
    return {'out0':out.reshape(w,w,(c+127)//128,128)}
