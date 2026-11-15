def fold(module, **params):
    import torch
    mods = list(module.children())
    if len(mods) < 2:
        mods = [module, module]
    out = {}
    for i in range(2):
        out[f'w{i}'] = mods[i].weight.detach().contiguous()
        if params[f's{i}_bias']:
            b = torch.zeros(params[f's{i}_n'], 128)
            b[:, 0] = mods[i].bias.detach()
            out[f'b{i}'] = b
    return out
