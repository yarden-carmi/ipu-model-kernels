import torch
def reference(**kw):
    x=kw['in0'].flatten().float()
    d=x[:,None]-torch.arange(kw['s0_vocab']).float()[None,:]
    y=torch.relu(1-d*d).double() @ kw['w'].double()+kw['add']
    mu=y.mean(-1,keepdim=True)
    var=((y-mu)**2).mean(-1,keepdim=True)
    return {'out0':(((y-mu)/torch.sqrt(var+kw['s2_eps']))*kw['gamma']+kw['beta']).unsqueeze(0)}
