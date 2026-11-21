import torch
import torch.nn.functional as F
def reference(**kw):
    ci,co,g,h,w,kh,kk=[int(kw[k]) for k in ('cin','cout','groups','h','w','kh','kw')]
    x=kw['in0'].reshape(h,w,-1)[...,:ci].permute(2,0,1)[None]
    if g == 1:
        wt=kw['weights'].reshape(co,kh,kk,-1)[...,:ci].permute(0,3,1,2)
    else:
        wt=kw['weights'][:,0].reshape(co,kh,kk,ci//g).permute(0,3,1,2)
    b=kw['bias_vec'][:,0] if kw['bias'] else None
    y=F.silu(F.conv2d(x,wt,b,stride=kw['stride'],padding=kw['padding'],groups=g))[0]
    out=torch.zeros(co,y.shape[2],128,dtype=y.dtype)
    out[...,:y.shape[1]]=y.permute(0,2,1)
    return {'out0':out.reshape(-1,128)}
