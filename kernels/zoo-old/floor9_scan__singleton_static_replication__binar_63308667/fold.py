def fold(module, **params):
    return {'table': module.table.reshape(-1).contiguous()}
