import torch

def reference(**kw):
    t, v, n = kw['s0_tokens'], kw['s0_vocab'], kw['s1_n']
    # Step 1 is supplied as a computed-at-home input by this task.
    x = kw['b'].reshape(t,n)
    mu = x.mean(-1, keepdim=True)
    var = (x-mu).square().mean(-1, keepdim=True)
    gamma, beta = kw['gamma'], kw['beta']
    y = (x-mu) / torch.sqrt(var+kw['s2_eps']) * gamma + beta
    return {'out0': y.reshape(1,t,n), 'out1': kw['b'].reshape(1,t,n)}
