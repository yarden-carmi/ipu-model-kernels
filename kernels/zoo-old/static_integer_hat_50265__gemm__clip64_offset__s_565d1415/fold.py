def fold(module, **params):
    return {'aux': module.weight.detach().contiguous()}
