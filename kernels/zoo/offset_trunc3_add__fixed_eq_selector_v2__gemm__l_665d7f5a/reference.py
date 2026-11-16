import torch

def reference(**kw):
    x = kw['in0'].reshape(-1) + 0
    selector = (x[:, None] == torch.arange(kw['s1_vocab'], device=x.device)).double()
    first = selector @ kw['w']
    index = kw['index'][:, :kw['s3_sel']]
    scan = first[:, :1].expand(index.shape).clone()
    for j in range(first.shape[1]):
        val = first[:, max(0,j-1):min(first.shape[1],j+2)].max(1, keepdim=True).values
        scan = torch.where(index == j, val.expand(index.shape), scan)
    second_selector = (scan.reshape(-1, 1) == torch.arange(kw['s4_vocab'], device=x.device)).double()
    return {'out0': first.unsqueeze(0), 'out1': (second_selector @ kw['v']).unsqueeze(0)}
