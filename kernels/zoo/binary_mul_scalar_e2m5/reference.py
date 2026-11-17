def reference(**kw):
    numel = kw["numel"]
    n = numel // 4096
    K = (n + 127) // 128
    tail = n - (K - 1) * 128
    out = kw["in0"] * kw["operand"].reshape(-1)[0]
    out[:, K - 1, tail:] = 0
    return {"out0": out}