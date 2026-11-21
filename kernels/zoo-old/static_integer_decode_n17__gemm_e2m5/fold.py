def fold(module, **params):
    result = {'w': module.weight.detach().contiguous()}
    if params['s1_bias']:
        result['b'] = module.bias.detach().contiguous()
    return result
