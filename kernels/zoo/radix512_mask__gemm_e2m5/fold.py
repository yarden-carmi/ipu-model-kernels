def fold(module, **params):
    result = {'w': module.weight.detach().contiguous()}
    if params.get('s1_bias', False):
        result['bias'] = module.bias.detach().contiguous()
    return result
