import torch

def reference(**kw):
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    w = kw['w'].to(torch.float64).reshape(vocab, n)
    out = torch.zeros(tokens, n, dtype=torch.float64)
    ok = (ids >= 0) & (ids < vocab)
    out[ok] = w[ids[ok]]
    return {'out0': out.reshape(-1, 128)}
