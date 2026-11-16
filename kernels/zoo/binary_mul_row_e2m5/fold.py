import torch


def fold(module, **params):
    operand = module.operand.reshape(-1, 64)
    return {"operand": torch.nn.functional.pad(operand, (0, 64))}
