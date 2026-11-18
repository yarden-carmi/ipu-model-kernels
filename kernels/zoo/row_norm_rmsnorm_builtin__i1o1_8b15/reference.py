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
    r0 = aten.reshape.default(module.weight, [1, -1, 1, 1])
    r1 = aten.reshape.default(module.bias, [1, -1, 1, 1])
    r2 = aten.reshape.default(module.running_var, [1, -1, 1, 1])
    r3 = aten.reshape.default(module.running_mean, [1, -1, 1, 1])
    r4 = aten.add.Tensor(module.running_var, 1e-05)
    r5 = aten.rsqrt.default(_l(r4, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    r6 = aten.mul.Tensor(module.weight, _l(r5, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    r7 = aten.mul.Tensor(module.running_mean, _l(r6, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    r8 = aten.sub.Tensor(module.bias, _l(r7, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    r9 = aten.mul.Tensor(_v(ins[0], [1, 32, 112, 112], [401408, 12544, 112, 1], 0), _l(r6, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    r10 = aten.add.Tensor(_l(r9, 0, [1, 32, 112, 112], [401408, 12544, 112, 1], 0), _l(r8, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0))
    op0 = _pick(r10, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 32, 112, 112], [401408, 12544, 112, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.pad.default(_v(op1, [1, 32, 112, 112], [401408, 12544, 112, 1], 0), [0, 1, 0, 1])
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 32, 113, 113])}
# ---- end of the frozen reference ----

def fold(module, **params):
    v = lambda t: _l(t, 0, [1, 32, 1, 1], [32, 1, 1, 1], 0)
    r5 = torch.rsqrt(v(module.running_var + 1e-5))
    r6 = module.weight * r5
    r8 = module.bias - v(module.running_mean * v(r6))
    result = {}
    for name, value in (("scale", v(r6).flatten()), ("bias", v(r8).flatten())):
        step = 2.0 ** (torch.floor(torch.log2(value.abs().max())).item() - 2)
        high = torch.round(value / step) * step
        result[name] = torch.nn.functional.pad(high, (0, 96))
        residual = value - high
        step2 = 2.0 ** (torch.floor(torch.log2(residual.abs().max())).item() - 2)
        middle = torch.round(residual / step2) * step2
        result[name + "_lo"] = torch.stack((
            torch.nn.functional.pad(middle, (0, 96)),
            torch.nn.functional.pad(residual - middle, (0, 96))))
    return result
