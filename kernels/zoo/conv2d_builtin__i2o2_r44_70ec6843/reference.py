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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 16, 16], [16384, 256, 16, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 64, 16, 16], [16384, 256, 16, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 64, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Build height-vector filters, with zeros at the vertical image edges."""
    w = module.weight.detach().to(torch.float64)
    cout, per_group, _, _ = w.shape
    groups, h = params['groups'], params['h']
    cin = per_group * groups
    dense = w.new_zeros((cout, cin, 3, 3))
    for g in range(groups):
        outputs = slice(g * (cout // groups), (g + 1) * (cout // groups))
        dense[outputs, g * per_group:(g + 1) * per_group] = w[outputs]
    chunks = (h + 127) // 128
    rows = w.new_zeros((chunks, cout, 1 + 9 * cin, 128))
    if params['bias']:
        rows[:, :, 0, :] = module.bias.reshape(1, cout, 1)
    taps = rows[:, :, 1:, :].view(chunks, cout, cin, 3, 3, 128)
    taps[:] = dense.transpose(2, 3)[None, ..., None]
    taps[0, :, :, :, 0, 0] = 0
    taps[-1, :, :, :, 2, (h - 1) % 128] = 0
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exp.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    return {'weights': torch.stack((hi, rows - hi), dim=-2).flatten(2, 3)}
