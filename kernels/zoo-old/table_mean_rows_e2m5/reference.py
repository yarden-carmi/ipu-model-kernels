def reference(**kw):
    return {"out0": kw["mean"].reshape(1, 1, kw["channels"]).expand(1, kw["rows"], kw["channels"])}
