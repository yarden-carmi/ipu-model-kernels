import torch

def reference(**kw):
    x = kw['in0'].reshape(-1)
    a = (x[:, None].to(torch.int64) == torch.arange(kw['s0_vocab'])).double() @ kw['w0']
    y = x + kw['in1'].reshape(-1)[0]
    b = (y[:, None].to(torch.int64) == torch.arange(kw['s3_vocab'])).double() @ kw['w4']
    c = kw['w7'].reshape(1, -1).expand(kw['s7_m'], -1)
    return {'out0': a.unsqueeze(0), 'out1': b.unsqueeze(0), 'out2': c.unsqueeze(0)}
