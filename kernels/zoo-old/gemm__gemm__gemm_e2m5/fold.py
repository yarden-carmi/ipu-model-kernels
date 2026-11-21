def fold(module, **params):
    import torch
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor) and m.weight.ndim == 2]
    assert len(layers) == 3
    result = {f'w{i}': m.weight.detach().T.contiguous() for i, m in enumerate(layers)}
    biases = [m.bias.detach() if m.bias is not None else m.weight.new_zeros(m.weight.shape[0]) for m in layers]
    result['biases'] = torch.cat([b.reshape(-1, 128) for b in biases], dim=0).contiguous()
    return result
