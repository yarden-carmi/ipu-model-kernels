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
    r5 = aten.rsqrt.default(_l(r4, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    r6 = aten.mul.Tensor(module.weight, _l(r5, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    r7 = aten.mul.Tensor(module.running_mean, _l(r6, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    r8 = aten.sub.Tensor(module.bias, _l(r7, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    r9 = aten.mul.Tensor(_v(ins[0], [1, 512, 28, 28], [401408, 784, 28, 1], 0), _l(r6, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    r10 = aten.add.Tensor(_l(r9, 0, [1, 512, 28, 28], [401408, 784, 28, 1], 0), _l(r8, 0, [1, 512, 1, 1], [512, 1, 1, 1], 0))
    op0 = _pick(r10, 0)  # step 0
    return {"out0": _out(op0, [1, 512, 28, 28])}
# ---- end of the frozen reference ----

def fold(module, **params):
    n = module.weight.numel()
    v = lambda t: torch.as_strided(t, (1, n, 1, 1), (n, 1, 1, 1), 0)
    scale = module.weight * torch.rsqrt(v(module.running_var + 1e-5))
    bias = module.bias - v(module.running_mean * v(scale))
    result = {}
    for name, value in (("scale", v(scale).flatten()), ("bias", v(bias).flatten())):
        padded = torch.nn.functional.pad(value, (0, (-n) % 128)).reshape(-1, 128)
        magnitude = padded.abs().amax(dim=1, keepdim=True)
        step = torch.where(magnitude > 0, 2.0 ** (torch.floor(torch.log2(magnitude)) - 4), torch.ones_like(magnitude))
        high = torch.round(padded / step) * step
        result[name] = high
        result[name + "_lo"] = padded - high
    return result
