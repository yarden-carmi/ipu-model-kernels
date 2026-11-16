def fold(module, **params):
    return {'v': module.weight.detach().contiguous()}
