def fold(module, **params):
    out={'w':module.weight.detach().t().contiguous()}
    if params.get('s1_bias'):
        out['b']=module.bias.detach().contiguous()
    return out
