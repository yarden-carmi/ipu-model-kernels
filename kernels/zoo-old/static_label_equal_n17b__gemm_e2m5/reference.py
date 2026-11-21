import torch
def reference(**kw):
    ids=kw['in0'][:kw['s0_tokens']].to(torch.int64)
    eq=(ids[:,None] == torch.arange(kw['s0_vocab'])).double()
    y=eq @ kw['w']
    if kw['s1_bias']: y=y+kw['b']
    return {'out0':y}
