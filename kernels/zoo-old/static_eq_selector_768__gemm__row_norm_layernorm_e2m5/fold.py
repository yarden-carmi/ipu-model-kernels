import torch

def fold(module, **params):
    return {
        'packed': module.weight.detach().contiguous(),
        'g': torch.stack((module.gamma.detach(), module.beta.detach())).contiguous(),
    }
