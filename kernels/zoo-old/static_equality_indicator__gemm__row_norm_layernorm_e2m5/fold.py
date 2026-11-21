import torch

def fold(module, **params):
    return {'packed': module.weight.detach().contiguous(),
            }
