import torch
def reference(**kw):
    r,c = kw['s4_rows'],kw['s4_channels']
    x = kw['table'].reshape(1,c) + kw['in1'].reshape(r,c) + kw['in2'].reshape(r,c)
    m=x.mean(1,keepdim=True)
    y=(x-m)/torch.sqrt(((x-m)**2).mean(1,keepdim=True)+kw['s4_eps'])
    y=y*kw['gamma'].reshape(1,c)+kw['beta'].reshape(1,c)
    out=torch.zeros(c,((r+127)//128)*128,dtype=y.dtype)
    out[:,:r]=y.T
    return {'out0':out}
