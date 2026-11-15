import torch

def reference(**kw):
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s1_k']), int(kw['s1_n'])
    ids = kw['in0'].reshape(-1)[:tokens].long()
    w = kw['w'].reshape(vocab, n)
    out = torch.zeros(tokens, n, dtype=torch.float64)
    valid = (ids >= 0) & (ids < vocab)
    out[valid] = w[ids[valid]]
    return {'out0': out.reshape(-1, 128)}
