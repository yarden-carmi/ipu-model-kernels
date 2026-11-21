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
    import types
    ins = tuple(t.clone() for t in ins)  # an in-place operation below writes on its own copies
    module = types.SimpleNamespace(**{k: v.clone() if hasattr(v, 'clone') else v
                                      for k, v in vars(module).items()})
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 1, 1], [16, 1, 1, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op0, [1, 8, 1, 1], [8, 1, 1, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 8, 1, 1])}
# ---- end of the frozen reference ----


import torch


def fold(module, **params):
    """Rows of 128 lanes (output channel in lane), per block of 128 output channels: the bias row, then one row per input
    channel (batch norm folded in when the module has one); each followed by its residual: the coarse row is on a
    power-of-two grid of its own row exponent (5 significant bits), the residual is what it left over (the host rounds it)."""
    n, k = int(params["n"]), int(params["k"])
    nb = (n + 127) // 128
    if hasattr(module, "op1_weight"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale.reshape(n, 1)
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = module.bias.double().reshape(n) if getattr(module, "bias", None) is not None else torch.zeros(n, dtype=torch.float64)
    rows = torch.zeros((nb * (k + 1), 128), dtype=torch.float64)
    for block in range(nb):
        lo, hi = 128 * block, min(n, 128 * (block + 1))
        base = block * (k + 1)
        if params.get("bias"):
            rows[base, :hi - lo] = bias[lo:hi]
        rows[base + 1:base + k + 1, :hi - lo] = weight[lo:hi].T
    _, exp = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exp, dtype=rows.dtype), exp - 4)
    coarse = torch.round(rows / step) * step
    packed = torch.zeros((2 * rows.shape[0], 128), dtype=rows.dtype)
    packed[::2] = coarse
    packed[1::2] = rows - coarse
    return {"coeff": packed.numpy()}
