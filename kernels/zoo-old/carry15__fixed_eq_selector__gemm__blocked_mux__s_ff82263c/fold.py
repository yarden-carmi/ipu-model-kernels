def fold(module, **params):
    return {'w': module.table.detach().contiguous(),
            'v': module.weight.detach().reshape(1, params['s5_n']).contiguous()}
