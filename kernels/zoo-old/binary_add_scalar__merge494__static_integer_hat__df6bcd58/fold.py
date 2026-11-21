def fold(module, **params):
    return {'table': module.table.detach().contiguous()}
