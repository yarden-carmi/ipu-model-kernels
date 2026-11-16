def reference(**kw):
    # The scan result supplies only the device to singleton replication;
    # no value from it contributes to the chain's output.
    table = kw['table']
    return {'out0': table.reshape(1, 1, kw['s1_dim']).expand(
        1, kw['s1_tokens'], kw['s1_dim']).clone()}
