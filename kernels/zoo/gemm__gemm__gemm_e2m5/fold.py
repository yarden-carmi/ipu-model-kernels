def fold(module, **params):
    import torch
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor) and m.weight.ndim == 2]
    assert len(layers) == 3
    return {f'w{i}': (m.weight.detach().T.contiguous() if i != 1 else m.weight.detach().contiguous()) for i, m in enumerate(layers)}
