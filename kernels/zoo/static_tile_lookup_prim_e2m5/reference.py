import torch


def reference(**kw):
    tokens, vocab, dim = int(kw['tokens']), int(kw['vocab']), int(kw['dim'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    table = kw['table'].to(torch.float64).reshape(vocab, dim)
    out = torch.zeros(tokens, dim, dtype=torch.float64)
    ok = (ids >= 0) & (ids < vocab)
    out[ok] = table[ids[ok]]
    return {'out0': out.reshape(-1, 128)}
