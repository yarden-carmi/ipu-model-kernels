def fold(module, **params):
    return {'in1': module.operand.reshape(-1), 'gamma': module.gamma.reshape(-1), 'beta': module.beta.reshape(-1)}
