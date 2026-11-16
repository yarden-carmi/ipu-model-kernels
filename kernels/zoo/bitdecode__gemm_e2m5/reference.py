import torch

def reference(**kw):
    ids = kw['in0'].reshape(-1).to(torch.int64)
    ramp = torch.arange(kw['s0_vocab'], device=ids.device, dtype=torch.int64)
    mask = torch.ones((ids.numel(), kw['s0_vocab']), dtype=torch.float64, device=ids.device)
    for bit in range((kw['s0_vocab'] - 1).bit_length()):
        mask *= 1 - (((ids[:, None] >> bit) ^ (ramp[None, :] >> bit)) & 1)
    return {'out0': (mask @ kw['w']).reshape(1, kw['s1_m'], kw['s1_n'])}
