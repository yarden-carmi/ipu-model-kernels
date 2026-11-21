def fold(module, **params):
    return {'w': module.weight.detach().contiguous(), 'gamma': module.gamma.detach().contiguous()}
