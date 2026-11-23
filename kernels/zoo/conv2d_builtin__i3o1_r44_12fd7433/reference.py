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
    r0 = aten.conv2d.default(_v(ins[0], [1, 1, 224, 224], [150528, 50176, 224, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op0, [1, 64, 224, 224], [3211264, 50176, 224, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 64, 224, 224])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack vectors by spatial tap, keeping residual rows for selected taps."""
    weight = module.weight.detach().to(torch.float64)
    cout = weight.shape[0]
    rows = weight.new_zeros((10, 128))
    rows[1:, :cout] = weight.reshape(cout, 9).T
    if params['bias']:
        rows[0, :cout] = module.bias

    # Preserve the part lost by quantizing the main row in a second row.
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    packed = []
    for i in range(10):
        if i in (1, 3, 7):
            packed.append(rows[i])
        else:
            packed.extend((hi[i], rows[i] - hi[i]))
    return {'weights': torch.stack(packed)}
