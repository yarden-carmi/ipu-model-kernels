import torch

def fold(module, **params):
    return {'w0': module.weight.detach().contiguous(),
            'w1': module.table.detach().contiguous()}
