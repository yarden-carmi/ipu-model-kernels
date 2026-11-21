# ---- frozen reference (stage 1): do not change ----
import torch


def reference(module, *ins, _round=None, **params):
    shape = (1, 1024, 14, 14)
    stride = (200704, 196, 14, 1)
    a = torch.as_strided(ins[0], shape, stride, 0)
    b = torch.as_strided(ins[1], shape, stride, 0)
    out = a + b
    out = torch.relu(out)
    return {"out0": out}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
