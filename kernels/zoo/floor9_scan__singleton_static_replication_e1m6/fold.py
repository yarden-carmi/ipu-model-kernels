def fold(module, **params):
    return {'table': module.table.reshape(1, params['s1_dim']).contiguous()}
