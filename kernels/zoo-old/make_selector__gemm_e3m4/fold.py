def fold(module, **params):
    return {'w': module.weight.detach().reshape(params['s0_vocab'], params['s1_n']).contiguous()}
