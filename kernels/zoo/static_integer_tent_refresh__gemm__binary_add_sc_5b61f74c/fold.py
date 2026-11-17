def fold(module, **params):
    return {'w1': module.table.detach().contiguous(),
            'v': module.weight.detach()[:1].contiguous()}
