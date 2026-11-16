def fold(module, **params):
    return {'table': module.table.reshape(1, params['s4_dim']).contiguous()}
