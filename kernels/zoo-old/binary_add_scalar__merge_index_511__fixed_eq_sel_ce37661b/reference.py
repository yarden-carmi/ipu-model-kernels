import torch
def reference(**kw):
    ids=kw['in0'].reshape(-1)+1
    ids=torch.where(ids==511,ids-1,ids)
    a=(ids[:,None]==torch.arange(kw['s2_vocab'])).double() @ kw['w']
    # block2_select's payload is ignored by singleton_units.
    b=torch.ones((kw['s5_tokens'],1),dtype=torch.float64) @ kw['v']
    return {'out0':a.reshape(1,kw['s3_m'],kw['s3_n']), 'out1':b.reshape(1,kw['s6_m'],kw['s6_n'])}
