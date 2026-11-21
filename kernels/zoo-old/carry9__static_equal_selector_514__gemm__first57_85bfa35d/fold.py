def fold(module, **params):
    return {'w': module.weight.detach().contiguous(),
            'v': module.table.detach()[0:1].contiguous()}
