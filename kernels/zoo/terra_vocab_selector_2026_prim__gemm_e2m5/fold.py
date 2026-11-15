def fold(module, **params):
    return {'w': (module.weight[:params['s1_k'], :params['s1_n']] * 0.5).contiguous()}
