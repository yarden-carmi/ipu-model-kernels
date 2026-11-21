import torch

def reference(**kw):
    ids=kw['in0'].reshape(-1)+1
    ids=ids-(ids==492).to(ids.dtype)
    a=(ids[:,None]==torch.arange(kw['s2_vocab'],device=ids.device)).float() @ kw['w'].float()
    index=kw['in0'].reshape(1,-1)
    selected=kw['table'][:,:1].expand(1,kw['s4_numel']).clone()
    for j in range(1,min(kw['table'].shape[1],16)):
        selected=torch.where(index==j,kw['table'][:,j:j+1].expand_as(selected),selected)
    b=(selected.reshape(-1,1)==torch.arange(kw['s5_vocab'],device=ids.device)).float() @ kw['v'].float()
    return {'out0':a.reshape(1,kw['s3_m'],kw['s3_n']), 'out1':b.reshape(1,kw['s6_m'],kw['s6_n'])}
