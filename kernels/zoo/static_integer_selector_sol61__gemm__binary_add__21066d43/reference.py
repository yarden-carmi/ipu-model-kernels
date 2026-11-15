import torch
def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    a = (ids[:,None] == torch.arange(kw['s0_vocab'])).double() @ kw['w']
    ids = kw['in1'].reshape(-1)[:kw['s2_numel']] + 1
    b = (ids[:,None] == torch.arange(kw['s3_vocab'])).double() @ kw['u']
    c = (b[:,kw['s5_sel']].long() == 0).double()[:,None] @ kw['v']
    return {'out0':a[None], 'out1':b[None], 'out2':c[None]}
