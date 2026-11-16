def reference(**kw):
    return {"out0": (kw["in0"].reshape(-1)[:kw["numel"]] * kw["operand"].reshape(-1)[0]).reshape(1, 128)}
