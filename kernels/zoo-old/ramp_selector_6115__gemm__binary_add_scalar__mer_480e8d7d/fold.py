def fold(module, **params):
    return {'w1': module.weight.detach().contiguous(),
            'w5': module.table.detach().contiguous(),
            'w8': module.weight.detach().contiguous()}
