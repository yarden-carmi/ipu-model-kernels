def fold(module, **params):
    return {'w': module.weight.detach().contiguous(), 'table': module.table.detach().contiguous()}
