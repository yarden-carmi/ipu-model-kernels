import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)
    bits = (kw['s0_vocab'] - 1).bit_length()
    ids = x.to(torch.int64) & ((1 << bits) - 1)
    a = (ids[:, None] == torch.arange(kw['s0_vocab'])).double() @ kw['w0']
    y = x + kw['in1'].reshape(-1)[0]
    y = y - (y == 490).to(y.dtype)
    b = (y[:, None] == torch.arange(kw['s4_vocab'])).double() @ kw['w5']
    # The mux feeds singleton_ones, whose input values are unused.
    c = torch.ones((kw['s7_tokens'], 1), dtype=x.dtype) @ kw['w8']
    return {'out0': a.unsqueeze(0), 'out1': b.unsqueeze(0), 'out2': c.unsqueeze(0)}
