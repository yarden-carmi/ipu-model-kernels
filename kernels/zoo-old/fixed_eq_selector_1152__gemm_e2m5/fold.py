def fold(module, **params):
    return {'w': module.weight.detach()[:params['s1_k'], :params['s1_n']].contiguous()}
