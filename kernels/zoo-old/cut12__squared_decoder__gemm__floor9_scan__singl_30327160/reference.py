def reference(**kw):
    # All preceding operations feed only the device argument of replication.
    result = kw['table'].reshape(1, 1, kw['s4_dim']).expand(
        1, kw['s4_tokens'], kw['s4_dim']).clone()
    return {'out0': result, 'out1': result.clone()}
