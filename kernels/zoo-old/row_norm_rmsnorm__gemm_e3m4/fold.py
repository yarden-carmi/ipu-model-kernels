import torch

def fold(module, **params):
    c = params['s0_channels']
    g = torch.zeros(128)
    g[:c] = module.gamma.detach().reshape(-1)
    out = {'gamma': g, 'w': module.weight.detach().t().contiguous()}
    if params['s1_bias']:
        out['b'] = module.bias.detach().contiguous()
    return out
