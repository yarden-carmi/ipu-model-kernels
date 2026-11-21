import torch


def fold(module, **params):
    """Pack embedding tables vocabulary-major, then unit/gamma/beta rows.

    Walk the fused module so constants belonging to later chain stages are
    obtained from their owning submodules rather than from the first weight.
    """
    modules = list(module.modules()) if hasattr(module, 'modules') else [module]
    tensors = []
    for owner in modules:
        for name in ('table', 'weight', 'weights', 'gamma', 'beta', 'bias'):
            value = getattr(owner, name, None)
            if isinstance(value, torch.Tensor):
                tensors.append((name, value.detach()))

    def table(k, n):
        for _, value in tensors:
            if tuple(value.shape) == (k, n):
                return value.contiguous()
            if tuple(value.shape) == (n, k):
                return value.t().contiguous()
        raise ValueError(f'missing embedding constant [{k}, {n}]')

    def affine(name, fallback):
        for key in (name, fallback):
            for attr, value in tensors:
                if attr == key and tuple(value.shape) == (params['s11_channels'],):
                    return value.reshape(-1)
        raise ValueError(f'missing layernorm {name}')

    return {
        'w': table(params['s1_k'], params['s1_n']),
        'p': table(params['s5_k'], params['s5_n']),
        'coeff': torch.stack((
            table(1, params['s8_n']).flatten(),
            affine('gamma', 'weight'), affine('beta', 'bias'),
        )).contiguous(),
    }
