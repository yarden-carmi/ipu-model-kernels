def fold(module, **params):
    return {'table': module.table.detach().contiguous(),
            'v': module.weight.detach()[:1].contiguous()}
