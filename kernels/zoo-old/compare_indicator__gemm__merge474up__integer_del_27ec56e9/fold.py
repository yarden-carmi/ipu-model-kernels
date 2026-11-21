def fold(module, **params):
    return {'w0': module.weight.detach().contiguous()}
