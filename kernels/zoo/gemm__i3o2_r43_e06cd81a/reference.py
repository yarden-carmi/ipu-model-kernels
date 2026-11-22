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
    r0 = aten.view.default(_v(ins[0], [1, 256, 768], [196608, 768, 1], 0), [-1, 768])
    r1 = aten.addmm.default(module.bias, _l(r0, 0, [256, 768], [768, 1], 0), module.weight)
    r2 = aten.view.default(_l(r1, 0, [256, 768], [768, 1], 0), [1, 256, 768])
    op0 = _pick(r2, 0)  # step 0
    return {"out0": _out(op0, [1, 256, 768])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Stream each bias/weight vector as three signed radix-16 planes."""
    k, n = int(params["k"]), int(params["n"])
    w = module.weight.detach().reshape(k, n).T.double()
    b = module.bias.detach().double() if params["bias"] else w.new_zeros(n)
    data = torch.cat((b[:, None], w), dim=1)
    rows = torch.nn.functional.pad(data, (0, 0, 0, (-n) % 128))
    rows = rows.reshape(-1, 128, k + 1).transpose(1, 2)
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(rows.abs(), 12 - exp).round().long().clamp(max=4095)
    planes = [torch.ldexp(((digits >> shift) & 15) * rows.sign(), exp + shift - 12)
              for shift in (8, 4, 0)]
    return {"w": torch.stack(planes, dim=2).reshape(-1, 128).float()}
