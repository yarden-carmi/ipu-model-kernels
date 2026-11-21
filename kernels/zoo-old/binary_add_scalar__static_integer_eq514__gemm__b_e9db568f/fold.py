def fold(module, **p):
    return dict(w=module.table.detach().t().contiguous(),
                v=module.weight.detach().reshape(1,p['s5_n']).contiguous())
