def fold(module, **params):
    import torch
    layers = [m for m in module.modules() if hasattr(m,'weight') and isinstance(m.weight,torch.Tensor) and m.weight.ndim == 2]
    assert len(layers) == 3
    parts = [m.weight.detach().T.contiguous().flatten() for m in layers]
    parts += [(m.bias.detach() if m.bias is not None else m.weight.new_zeros(m.weight.shape[0])).flatten() for m in layers]
    operands = [m.operand.detach().flatten() for m in module.modules() if hasattr(m,'operand') and isinstance(m.operand,torch.Tensor)]
    assert len(operands) == 4
    return {'constants': torch.cat(parts+operands).reshape(-1,128)}
