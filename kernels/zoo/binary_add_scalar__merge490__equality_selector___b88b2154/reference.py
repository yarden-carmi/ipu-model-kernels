import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1)[:kw['s0_numel']] + kw['scalar'].reshape(-1)[0]
    ids = ids - (ids == 490).to(ids.dtype)
    sel = (ids[:, None] == torch.arange(kw['s2_vocab'], device=ids.device)[None, :]).double()
    first = sel @ kw['w']
    # mux3_zero feeds singleton_ones, which ignores its values.
    second = torch.ones((kw['s5_tokens'], 1), dtype=ids.dtype, device=ids.device) @ kw['v']
    return {'out0': first.unsqueeze(0), 'out1': second.unsqueeze(0)}
