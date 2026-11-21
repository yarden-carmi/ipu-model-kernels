def fold(module, **params):
    return {'w': module.table.detach().contiguous()}
