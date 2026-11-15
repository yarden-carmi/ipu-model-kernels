def fold(module, **params):
    return {'w': module.table.detach().contiguous(), 'v': module.weight.detach().contiguous()}
