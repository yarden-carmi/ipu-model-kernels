def fold(module, **params):
    return {'w1': module.table.detach().contiguous(),
            'v': module.weight.detach().reshape(1, params['s7_n']).contiguous()}
