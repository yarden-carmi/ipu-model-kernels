# ---- frozen reference (stage 1): do not change ----
import torch


def reference(module, *ins, _round=None, **params):
    shape = (1, 256, 56, 56)
    stride = (802816, 3136, 56, 1)
    a = torch.as_strided(ins[0], shape, stride, 0)
    b = torch.as_strided(ins[1], shape, stride, 0)
    out = a + b
    positive = out > 0
    if _round is not None:
        out = _round(out, "s0")
    out = torch.where(out > 0, out, torch.zeros_like(out))
    if _round is not None:
        out = _round(out, "s0")
    out = torch.where(positive, out, torch.zeros_like(out))
    return {"out0": out}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
