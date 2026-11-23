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
    r0 = aten.conv2d.default(_v(ins[0], [1, 32, 224, 224], [1605632, 50176, 224, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 1, 224, 224], [50176, 50176, 224, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 1, 224, 224])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Keep each scalar's coarse and residual components in separate quantization rows."""
    n, k = int(params["n"]), int(params["k"])
    values = torch.zeros((n, k + 1), dtype=torch.float64)
    values[:, 1:] = module.weight.reshape(n, k)
    if params["bias"] and getattr(module, "bias", None) is not None:
        values[:, 0] = module.bias.reshape(n)
    _, exponent = torch.frexp(values.abs())
    step = torch.ldexp(torch.ones_like(values), exponent - 4)
    coarse = torch.round(values / step) * step
    rows = torch.zeros((n, k + 1, 2, 128), dtype=values.dtype)
    rows[..., 0] = torch.stack((coarse, values - coarse), dim=-1)
    rows[:, 0] = rows[:, 0, :, :1].expand(-1, -1, 128).clone()
    return {"coeff": rows.reshape(-1, 128).numpy()}
