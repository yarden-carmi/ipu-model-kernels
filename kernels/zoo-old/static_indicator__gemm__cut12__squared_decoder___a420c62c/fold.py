def fold(module, **params):
    import torch
    modules = list(module.modules())
    tables = [m.table for m in modules if hasattr(m, 'table') and isinstance(m.table, torch.Tensor)]
    embedding = next((t for t in tables if tuple(t.shape) == (params['s0_vocab'], params['s1_n'])), module.weight)
    singleton = next((t for t in tables if t.numel() == params['s6_dim']), None)
    if singleton is None:
        singleton = module.table[:1]
    result = {'w': embedding.detach().contiguous(), 'table': singleton.detach().reshape(1, -1).contiguous()}
    for name in ('gamma', 'beta'):
        owner = next((m for m in modules if hasattr(m, name)), None)
        if owner is not None:
            result[name] = getattr(owner, name).detach().contiguous()
    return result
