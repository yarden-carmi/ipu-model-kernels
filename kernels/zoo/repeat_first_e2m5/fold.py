def fold(module, **params):
    return {"in0": module.table[:1, :params["channels"]].contiguous()}
