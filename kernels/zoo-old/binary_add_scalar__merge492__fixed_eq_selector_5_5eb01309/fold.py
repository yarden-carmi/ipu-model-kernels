def fold(module, **params):
    return {'w': module.table.detach().contiguous(), 'v': module.weight.detach().contiguous().reshape(-1)[:params['s6_n']].reshape(1, params['s6_n'])}
