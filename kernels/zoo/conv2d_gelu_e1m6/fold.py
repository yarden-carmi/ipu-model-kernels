def fold(module, **params):
    w = module.weights
    return {'weights': w.permute(2, 3, 1, 0).contiguous().reshape(-1, w.shape[0])}
