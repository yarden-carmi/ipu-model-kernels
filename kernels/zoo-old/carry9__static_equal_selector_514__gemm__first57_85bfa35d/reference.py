import torch

def reference(**kw):
    a = kw['in0'].long().reshape(-1)
    b = torch.ones_like(a)
    s, c = a ^ b, (a & b) << 1
    for _ in range(9):
        s, c = s ^ c, (s & c) << 1
    selector = (s[:, None] == torch.arange(kw['s1_vocab'])[None, :]).double()
    y = selector @ kw['w']
    # first57_mux is consumed only by the value-independent singleton copy.
    return {'out0': y.unsqueeze(0),
            'out1': kw['v'].reshape(1, 1, kw['s4_dim']).expand(1, kw['s4_tokens'], -1).clone()}
