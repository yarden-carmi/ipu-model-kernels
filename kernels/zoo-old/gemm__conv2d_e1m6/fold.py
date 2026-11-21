import torch

def fold(module, **p):
    a,b = module[0],module[1]
    w0 = torch.zeros(p['s0_n'],2,128)
    w0[:,1,:p['s0_k']] = a.weight.detach()
    if p['s0_bias']: w0[:,0,0] = a.bias.detach()
    w1 = torch.zeros(1+p['s1_cin']*p['s1_kh']*p['s1_kw'],128)
    w1[1:,:p['s1_cout']] = b.weight.detach().permute(1,2,3,0).reshape(-1,p['s1_cout'])
    if p['s1_bias']: w1[0,:p['s1_cout']] = b.bias.detach()
    return {'w0':w0.reshape(-1,128),'w1':w1}
