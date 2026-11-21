import torch

def reference(**kw):
    x = kw['in0'].reshape(-1) + 0
    selector = (x[:, None] == torch.arange(kw['s1_vocab'], device=x.device)).double()
    first = selector @ kw['w']
    index = kw['index'][:, :kw['s3_sel']].long()
    selected = first.gather(1, (index // 2) * 2)
    second = (selected.reshape(-1, 1) == torch.arange(kw['s4_vocab'], device=x.device)).double()
    return {'out0': first.unsqueeze(0), 'out1': (second @ kw['v']).unsqueeze(0)}
