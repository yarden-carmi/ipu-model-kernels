def fold(module, **params):
    return {'weights': module.weight.detach().contiguous()}
