import torch
import torch.nn.functional as F

def reference(**kw):
    ci, co, h, w, kh, kx = [int(kw[k]) for k in ('cin','cout','h','w','kh','kw')]
    nb = (ci+127)//128
    x = kw['in0'].reshape(h,w,nb*128)[...,:ci].permute(2,0,1).unsqueeze(0)
    wf = kw['weights'].reshape(co,kh*kx*nb+1,128)
    if ci == 1 and kw['padding'] == 0:
        blocks = (kh*kx+127)//128
        packed = kw['weights'].reshape(-1)[:co*(blocks+int(kw['bias']))*128].reshape(co,-1)
        weight = packed[:,:kh*kx].reshape(co,1,kh,kx)
        b = packed[:,blocks*128] if kw['bias'] else None
    else:
        weight = wf[:,:-1].reshape(co,kh,kx,nb*128)[...,:ci].permute(0,3,1,2).contiguous()
        b = wf[:,-1,0] if kw['bias'] else None
    y = F.conv2d(x,weight,b,stride=kw['stride'],padding=kw['padding'],groups=kw['groups'])[0]
    out = torch.zeros(co,y.shape[2],128,dtype=torch.float64)
    out[...,:y.shape[1]] = y.permute(0,2,1)
    return {'out0':out.reshape(-1,128)}
