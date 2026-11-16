def fold(module, **p):
    w = module.weights
    return dict(weights=w.permute(2,3,1,0).reshape(-1,128), bias=module.bias.reshape(-1,128), operand=module.operand.reshape(-1,128), gamma=module.gamma.reshape(-1,128), beta=module.beta.reshape(-1,128))
