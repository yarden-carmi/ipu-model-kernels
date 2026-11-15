def fold(module, **params):
    w = module.weight.detach()
    v, n = int(params['s0_vocab']), int(params['s1_n'])
    assert tuple(w.shape) == (v, n)
    out = {'w': w.contiguous()}
    if params.get('s1_bias'):
        out['b'] = module.bias.detach().contiguous()
    return out
