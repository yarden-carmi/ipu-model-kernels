# ---- frozen reference (stage 1): do not change ----
"""The call's reference: the model's own operation, written by the harness (spec §4.9 Two stages).
Each operation is the model's own ATen call with its recorded arguments; an input is read through its
recorded view with torch.as_strided."""
import torch

def _v(t, shape, stride, offset):
    """A tensor read through its recorded view (shape, stride, offset on its storage)."""
    if not stride:
        return t.reshape(shape)
    return torch.as_strided(t, tuple(shape), tuple(stride), int(offset))


def _l(res, k, shape, stride, offset):
    """A record's own earlier result k, read as the model read it."""
    t = _pick(res, k)
    if list(t.shape) == list(shape) and (not stride or (list(t.stride()) == list(stride)
                                                         and t.storage_offset() == int(offset))):
        return t
    return _v(t, shape, stride, offset)


def _p(t, shape):
    """A parameter read at the shape its record read it (a view of it: reshaped, or expanded)."""
    if list(t.shape) == list(shape):
        return t
    n = 1
    for d in shape:
        n *= int(d)
    return t.reshape(tuple(shape)) if t.numel() == n else t.expand(tuple(shape))


def _pick(res, k):
    """Result k of a record (one tensor, or a tuple of them)."""
    return res[k] if isinstance(res, (tuple, list)) else res


def _out(t, shape):
    """An output in its stored shape."""
    return t.contiguous().reshape(tuple(shape))


def _sub(module, prefix):
    """The natural parameters of one operation of the call, by their own names."""
    import types
    return types.SimpleNamespace(**{k[len(prefix):]: v for k, v in vars(module).items() if k.startswith(prefix)})


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 128, 128], [1048576, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 32, 128, 128], [524288, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 32, 128, 128])}
# ---- end of the frozen reference ----

import numpy as np
import torch


def fold(module, **params):
    """Rows of 128 lanes (output channel in lane): bias hi, bias lo, then for each input channel its hi row and lo row,
    and one zero row that the streaming reads last. Batch norm is folded in when the module has one (op0_weight / op1_*),
    otherwise the plain weight and bias. hi is on a power-of-two grid of its row exponent (4 bits below the top, held
    exactly by every format with 4 or more mantissa bits); lo is what hi left over (the host rounds it)."""
    n, k = int(params["n"]), int(params["k"])
    if hasattr(module, "op1_weight"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale.reshape(n, 1)
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = module.bias.double().reshape(n) if getattr(module, "bias", None) is not None else torch.zeros(n, dtype=torch.float64)
    vec = torch.zeros((k + 1, 128), dtype=torch.float64)
    if params.get("bias", True):
        vec[0, :n] = bias
    vec[1:, :n] = weight.T
    _, exp = torch.frexp(vec.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exp, dtype=vec.dtype), exp - 4)
    hi = torch.round(vec / step) * step
    lo = vec - hi
    out = torch.zeros((2 * k + 3, 128), dtype=torch.float64)
    out[0], out[1] = hi[0], lo[0]
    out[2:2 * k + 2:2] = hi[1:]
    out[3:2 * k + 2:2] = lo[1:]
    return {"w": out.numpy()}
