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
    r0 = aten.mul.Tensor(_v(ins[0], [4, 4, 256, 36], [110592, 36, 432, 1], 0), 0.16666666666666666)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [4, 4, 256, 36])}
# ---- end of the frozen reference ----


def fold(module, **params):
    import math
    import torch
    # the scalar is head_dim ** -0.5; two frames: hi keeps 2 fraction bits (exact in every format with >= 2), lo = the rest (>= 0, smaller than hi, so both products have the sign of x)
    s = float(params["out0_d3"]) ** -0.5
    m, e = math.frexp(s)
    hi = math.ldexp(math.floor(m * 8) / 8, e)
    lo = s - hi
    return {"operand": torch.stack([torch.full((128,), hi), torch.full((128,), lo)])}
