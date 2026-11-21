import torch
import torch.nn.functional as F

def reference(**kw):
    ci, co, h, w, kh, kx = [int(kw[k]) for k in ('cin','cout','h','w','kh','kw')]
    x = kw['in0'].reshape(h,w,-1)[...,:ci].permute(2,0,1).unsqueeze(0)
    weight = kw['weights'].reshape(-1,128)[:,0].reshape(co,ci//kw['groups'],kh,kx)
    y = F.conv2d(x,weight,None,stride=kw['stride'],padding=kw['padding'],groups=kw['groups'])[0]
    out = torch.zeros(co,y.shape[1],128,dtype=torch.float64)
    out[...,:y.shape[2]] = y
    return {'out0':out}
