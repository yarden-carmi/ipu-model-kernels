import torch

def reference(**kw):
    position = torch.clamp(kw['in0'].float() + 1, max=255)
    ids = position.reshape(-1, 1).long()
    labels = torch.arange(kw['s1_vocab'], device=ids.device)
    y = (ids == labels).float() @ kw['w'].float()
    if kw['s2_bias']:
        y = y + kw['b'].float()
    index = kw['in0']
    a = kw['table'][:, :]
    selected = None
    for start in range(0, a.shape[1], 53):
        z = a[:, start:start+53].mean(1, keepdim=True).expand(index.shape)
        selected = z if selected is None else torch.where(index >= start, z, selected)
    result = kw['v'].reshape(1, kw['s4_dim']).expand(kw['s4_tokens'], -1).clone()
    return {'out0': y.reshape(1, kw['s2_m'], kw['s2_n']),
            'out1': result.reshape(1, kw['s4_tokens'], kw['s4_dim'])}
