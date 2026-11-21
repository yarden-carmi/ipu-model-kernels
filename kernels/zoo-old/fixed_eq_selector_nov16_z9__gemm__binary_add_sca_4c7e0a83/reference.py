import torch

def reference(**kw):
    ids0 = kw['in0'].reshape(-1)
    a = (ids0[:, None] == torch.arange(kw['s0_vocab'])).double() @ kw['w0']
    if kw['s1_bias']:
        a = a + kw['b0']
    ids1 = kw['in1'].reshape(-1) + 1
    ids1 = torch.where(ids1 == 511, ids1 - 1, ids1)
    b = (ids1[:, None] == torch.arange(kw['s4_vocab'])).double() @ kw['w1']
    # block2_select feeds singleton_units, whose result is independent of its input.
    c = torch.ones((kw['s7_tokens'], 1), dtype=torch.float64) @ kw['v']
    if kw['s8_bias']:
        c = c + kw['b2']
    return {'out0': a.reshape(1,kw['s1_m'],kw['s1_n']),
            'out1': b.reshape(1,kw['s5_m'],kw['s5_n']),
            'out2': c.reshape(1,kw['s8_m'],kw['s8_n'])}
