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
    r0 = aten.linear.default(_v(ins[0], [4, 64, 192], [12288, 192, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [4, 64, 192])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Store the bias and successive scalar weight panels for each channel."""
    n, k = module.weight.shape
    weight = module.weight.detach()
    bias = module.bias.detach() if params["bias"] else weight.new_zeros(n)
    d3 = params['in0_d3']
    width = d3 * (2 if d3 <= 64 and params['in0_d2'] % 2 == 0 and k % (2 * d3) == 0 else 1)
    chunk = width if params['m'] > 256 and k == 2 * width else 128
    rows = torch.nn.functional.pad(weight, (0, (-k) % chunk)).reshape(n, -1, chunk)
    rows = torch.nn.functional.pad(rows, (0, 128 - chunk))
    rows = torch.cat((bias[:, None, None].expand(-1, 1, 128), rows), dim=1)
    return {"w": rows.reshape(-1, 128)}
