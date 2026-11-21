import torch

def reference(**kw):
    x = kw['in0'].long().reshape(-1)
    y = torch.ones_like(x)
    for _ in range(15):
        x, y = x ^ y, (x & y) << 1
    selector = (x[:, None] == torch.arange(kw['s1_vocab'])[None, :]).double()
    first = selector @ kw['w']
    if kw['s2_bias']:
        first = first + kw['bias']
    # The blocked mux feeds a singleton selector independent of its values.
    unit = torch.ones((kw['s4_tokens'], kw['s4_vocab']), dtype=torch.float64)
    return {'out0': first.unsqueeze(0), 'out1': (unit @ kw['v']).unsqueeze(0)}
