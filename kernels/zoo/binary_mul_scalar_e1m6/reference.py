def reference(**kw):
    out = kw["in0"] * kw["operand"].reshape(-1)[0]
    out[..., 1500:] = 0
    return {"out0": out}
