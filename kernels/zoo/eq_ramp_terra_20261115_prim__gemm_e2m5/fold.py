def fold(module, **params):
    # The weights are kept in [vocab, n] order: row k holds the n outputs for index k.
    return {"weights": module.weight}
