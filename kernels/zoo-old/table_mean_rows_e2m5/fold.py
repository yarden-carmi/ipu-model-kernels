import torch


def fold(module, **params):
    return {"mean": module.table.to(dtype=torch.float64).mean(dim=0, keepdim=True)}
