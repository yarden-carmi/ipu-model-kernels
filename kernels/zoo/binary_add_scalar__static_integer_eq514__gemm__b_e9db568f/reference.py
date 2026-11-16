import torch

def reference(**kw):
    x=kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    eq=(x.long()[:,None] == torch.arange(kw['s1_vocab'])[None,:]).double()
    first=eq @ kw['w']
    # The bounded mux feeds a singleton unit generator, independent of its values.
    idx=x.long().reshape(-1,1)
    mux=torch.where(idx == 1,first[:,1:2],first[:,:1])
    unit=torch.ones((kw['s4_tokens'],kw['s4_vocab']),dtype=mux.dtype)
    return dict(out0=first.unsqueeze(0),out1=(unit @ kw['v']).unsqueeze(0))
