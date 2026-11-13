def reference(**kw):
    """out0 = in0 + second operand, elementwise, no broadcast.

    The second operand is the scalar `const` when the case gives a nonzero
    one, else the constant tensor `in1` (the operand computed at home).
    """
    in0 = kw["in0"]
    const = kw.get("const", 0.0) or 0.0
    if const != 0:
        out0 = in0 + float(const)
    else:
        out0 = in0 + kw["in1"]
    return {"out0": out0}
