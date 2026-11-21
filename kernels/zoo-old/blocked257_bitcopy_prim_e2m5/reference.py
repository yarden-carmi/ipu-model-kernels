import torch

def reference(**kw):
    tokens, vocab, dim = int(kw['tokens']), int(kw['vocab']), int(kw['dim'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    table = kw['table'].to(torch.float64).reshape(vocab, dim)
    out = table[ids]
    return {'out0': out.reshape(-1, 128)}
