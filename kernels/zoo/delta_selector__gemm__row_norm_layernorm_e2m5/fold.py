def fold(module, **params):
    return {'w': module.weight.detach().reshape(params['s1_k'], params['s1_n']).contiguous()}
