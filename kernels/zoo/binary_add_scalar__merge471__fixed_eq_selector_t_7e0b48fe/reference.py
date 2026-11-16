import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1) + kw['scalar'].flatten()[0]
    ids = torch.where(ids == 471, ids - 1, ids)
    selector = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)).double()
    first = selector @ kw['w']
    # zero_lane_read feeds a constant unit column, independent of its values.
    unit = torch.ones((kw['s5_tokens'], kw['s5_vocab']), dtype=torch.float64, device=ids.device)
    return {'out0': first.unsqueeze(0), 'out1': (unit @ kw['v']).unsqueeze(0)}
