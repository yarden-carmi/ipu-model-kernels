import torch
import torch.nn.functional as F

def reference(**kw):
    ci, co, h, w, kh, kx = [int(kw[k]) for k in ('cin','cout','h','w','kh','kw')]
    cp = ((co+127)//128)*128
    x = kw['in0'].reshape(h,w,-1)[...,:ci].permute(2,0,1).unsqueeze(0)
    weight = kw['weights'].reshape(kh,kx,ci,cp)[...,:co].permute(3,2,0,1).contiguous()
    b = kw['bias_vec'].reshape(-1)[:co] if kw['bias'] else None
    y = F.conv2d(x,weight,b,stride=kw['stride'],padding=kw['padding'],groups=kw['groups'])[0]
    out = torch.zeros(y.shape[1],y.shape[2],cp,dtype=torch.float64)
    out[...,:co] = y.permute(1,2,0)
    return {'out0':out.reshape(-1,128)}
