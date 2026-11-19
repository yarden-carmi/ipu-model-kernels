# ---- frozen reference (stage 1): do not change ----
import torch


def reference(module, *ins, _round=None, **params):
    shape = (1, 512, 28, 28)
    stride = (401408, 784, 28, 1)
    x = torch.as_strided(ins[0], shape, stride, 0)
    y = torch.as_strided(ins[1], shape, stride, 0)
    out = x.clone()
    out.add_(y)
    out = torch.relu(out)
    return {"out0": out}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
