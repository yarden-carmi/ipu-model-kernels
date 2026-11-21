def fold(module, **params):
    return {'v': module.weight.detach().contiguous().reshape(1,params['s5_n'])}
