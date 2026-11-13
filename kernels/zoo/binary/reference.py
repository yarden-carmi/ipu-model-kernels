import torch


def reference(in0, in1, broadcast="none", op="add", const=1.0, reciprocal=False,
              inner=0, numel=None, **_):
    x = in0.reshape(-1)
    n = int(numel) if numel is not None else x.numel()
    x = x[:n]
    rows = (n + 127) // 128
    if broadcast == "none":
        other = in1.reshape(-1)[:n]
    elif broadcast == "scalar":
        c = float(const)
        other = torch.full_like(x, (1.0 / c) if reciprocal else c)
    elif broadcast == "row":
        t = in1.reshape(-1)[:inner]
        other = t.repeat((n + inner - 1) // inner)[:n]
    else:  # col: one scalar per inner-element row of in0
        t = in1.reshape(-1)[: (n // inner) + 1]
        other = t.repeat_interleave(inner)[:n]
    y = x + other if op == "add" else x * other
    out = torch.zeros(rows * 128, dtype=y.dtype)
    out[:n] = y
    return {"out0": out.reshape(rows, 128)}
