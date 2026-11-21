import torch
def reference(**kw):
    x=kw['in0'].reshape(-1,1).float()
    j=torch.arange(kw['s0_vocab']).float()[None,:]
    y=(1-(x-j).abs()).clamp_min(0).double() @ kw['w']
    if kw['s1_bias']: y=y+kw['b']
    return {'out0':y.reshape(1,kw['s1_m'],kw['s1_n'])}
