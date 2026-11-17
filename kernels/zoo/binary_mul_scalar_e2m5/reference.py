def reference(**kw):
    out = kw["in0"] * kw["operand"].reshape(-1)[0]
    out[..., 197:] = 0
    return {"out0": out}
