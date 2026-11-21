import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)
    vocab = int(kw['s0_vocab'])
    indicators = (ids[:, None] == torch.arange(vocab, device=ids.device)[None, :]).to(torch.float64)
    out = indicators @ kw['w'].reshape(vocab, int(kw['s1_n']))
    if kw['s1_bias']:
        out = out + kw['b'].reshape(1, -1)
    return {'out0': out.reshape(1, int(kw['s1_m']), int(kw['s1_n']))}
