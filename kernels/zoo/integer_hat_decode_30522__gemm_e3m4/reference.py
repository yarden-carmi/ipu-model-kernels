import torch

def reference(**kw):
    tokens, vocab = int(kw['s0_tokens']), int(kw['s0_vocab'])
    x = kw['in0'].reshape(tokens, 1).to(torch.int64)
    d = x - torch.arange(vocab, device=x.device).reshape(1, -1)
    indicator = (1 - d.abs().clamp(max=1)).to(torch.float64)
    y = indicator @ kw['w'].reshape(int(kw['s1_k']), int(kw['s1_n']))
    return {'out0': y.reshape(1, int(kw['s1_m']), int(kw['s1_n']))}
