import torch

def reference(**kw):
    assert int(kw['s0_tokens']) == int(kw['s1_m'])
    assert int(kw['s0_vocab']) == int(kw['s1_k'])
    ids = kw['in0'].reshape(-1)[:int(kw['s1_m'])].long()
    w = kw['w'].reshape(int(kw['s0_vocab']), int(kw['s1_n']))
    out = torch.zeros((int(kw['s1_m']), int(kw['s1_n'])), dtype=torch.float64)
    # A one-hot selector times the weight matrix is exactly a row gather.
    # Like torch.one_hot, reject indices outside the vocabulary.
    assert bool(((ids >= 0) & (ids < int(kw['s0_vocab']))).all())
    out[:] = w[ids]
    return {'out0': out.reshape(1, int(kw['s1_m']), int(kw['s1_n']))}
