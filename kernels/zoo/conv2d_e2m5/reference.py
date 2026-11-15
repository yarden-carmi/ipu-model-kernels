import torch
import torch.nn.functional as F

def reference(**kw):
    ci, co, h, w, kh, kwd = [int(kw[k]) for k in ('cin','cout','h','w','kh','kw')]
    nb = (ci + 127) // 128
    x = kw['in0'].reshape(h, w, nb*128)[..., :ci].permute(2,0,1).unsqueeze(0)
    groups = int(kw['groups'])
    cg = ci // groups
    nw = (cg + 127) // 128
    wf = kw['weights'].reshape(co, 1+kh*kwd*nw, 128)
    weight = wf[:,1:].reshape(co,kh,kwd,nw*128)[...,:cg].permute(0,3,1,2).contiguous()
    b = wf[:,0,0] if kw['bias'] else None
    y = F.conv2d(x,weight,b,stride=kw['stride'],padding=kw['padding'],groups=groups)[0]
    out = torch.zeros(co,y.shape[2],128,dtype=torch.float64)
    out[...,:y.shape[1]] = y.permute(0,2,1)
    return {'out0':out}
