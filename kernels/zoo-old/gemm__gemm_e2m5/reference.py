def reference(**kw):
    x = kw['in0'].reshape(kw['s0_m'], kw['s0_k'])
    a = x @ kw['w0'].T
    if kw['s0_bias']:
        a = a + kw['b0'].sum(dim=1)
    b = x.reshape(kw['s1_m'], kw['s1_k']) @ kw['w1'].T
    if kw['s1_bias']:
        b = b + kw['b1'].sum(dim=1)
    return {'out0': a[None, None], 'out1': b.T.contiguous()[None, None]}
