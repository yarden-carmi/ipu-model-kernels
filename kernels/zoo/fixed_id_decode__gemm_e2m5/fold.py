def fold(module, **params):
    # The gemm's own weight is [vocab, n] = [k, n], vocabulary-major, which is
    # exactly the layout the kernel wants: row k of the constant holds the
    # weights for vocabulary id k, with the n dimension along the 128 lanes.
    return {'weights': module.weight.detach().contiguous()}
