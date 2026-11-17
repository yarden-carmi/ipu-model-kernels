def fold(module, **params):
    c, f = params['channels'], params['features']
    return {'w': module.weight.detach().reshape(c, f).t().contiguous().reshape(f, c // 128, 128),
            'b': module.bias.detach().reshape(c).contiguous()}
