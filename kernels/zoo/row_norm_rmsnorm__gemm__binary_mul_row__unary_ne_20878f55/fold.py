def fold(module, **params):
    import torch
    ms=list(module.modules())
    layer=next(m for m in ms if hasattr(m,'weight') and isinstance(m.weight,torch.Tensor) and m.weight.ndim==2)
    gamma=next(m.gamma for m in ms if hasattr(m,'gamma'))
    operands=[m.operand.detach().flatten() for m in ms if hasattr(m,'operand') and isinstance(m.operand,torch.Tensor)]
    bias=layer.bias.detach() if layer.bias is not None else layer.weight.new_zeros(layer.weight.shape[0])
    return {'constants':torch.cat([gamma.detach().flatten(),layer.weight.detach().T.contiguous().flatten(),bias]+operands).reshape(-1,128)}
