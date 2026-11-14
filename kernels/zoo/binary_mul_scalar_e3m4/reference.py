def reference(**kw):
    in0 = kw["in0"]
    s = float(kw["const"])
    return {"out0": in0 * s}
