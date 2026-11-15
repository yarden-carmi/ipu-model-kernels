import torch

def reference(**kw):
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    w = kw['w'].to(torch.float64).reshape(vocab, n)
    indicators = torch.nn.functional.one_hot(ids, num_classes=vocab).to(torch.float64)
    return {'out0': (indicators @ w).reshape(1, int(kw['s1_m']), n)}
