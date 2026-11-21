def fold(module, **params):
    return {'w5': module.table.detach().contiguous(),
            'w8': module.weight.detach().contiguous().reshape(-1)[:params['s8_n']].reshape(1, params['s8_n'])}
