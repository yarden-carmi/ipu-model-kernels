def fold(module, **params):
    return {'w': module.weight.detach().contiguous().reshape(params['s5_k'], params['s5_n'])}
