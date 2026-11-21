def fold(module, **params):
    return {'table': module.table.detach().contiguous(),
            'w': module.weight.detach().contiguous(),
            'v': module.table.detach()[0:1].contiguous()}
