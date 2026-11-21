def reference(**kw):
    import torch
    x = kw['in0'].reshape(-1)[:kw['s0_numel']] + 1
    ids = torch.div(x, 4, rounding_mode='floor') * 4
    prior = torch.full((kw['s2_tokens'], kw['s2_dim']), 0.01, dtype=torch.float64)
    # All source entries are identical: static predicated selection retains
    # the same floating payload for every possible index.
    selected = prior[:kw['s4_tokens'], :1].reshape(-1)
    indicator = (selected[:, None] == torch.arange(kw['s4_vocab'])[None, :]).double()
    result = indicator @ kw['w'].reshape(kw['s5_k'], kw['s5_n'])
    return {'out0': prior.unsqueeze(0), 'out1': result.unsqueeze(0)}
