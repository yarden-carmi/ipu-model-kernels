def fold(module, **params):
    import torch
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor) and m.weight.ndim == 2]
    assert len(layers) == 3
    result = {f'w{i}': (m.weight.detach().T.contiguous() if i != 1 else m.weight.detach().contiguous()) for i, m in enumerate(layers)}
    biases = [m.bias.detach() if m.bias is not None else m.weight.new_zeros(m.weight.shape[0]) for m in layers]
    result['biases'] = torch.cat([biases[0].reshape(-1, 128), biases[1][:, None].expand(-1, 128), biases[2].reshape(-1, 128)], dim=0).contiguous()
    return result
