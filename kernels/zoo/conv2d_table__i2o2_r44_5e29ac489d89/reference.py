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
    r0 = aten.conv2d.default(_v(ins[0], [1, 160, 8, 8], [10240, 64, 8, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 160, 8, 8], [10240, 64, 8, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 160, 8, 8], [10240, 64, 8, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 160, 8, 8])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold batch norm and pack weights for the spatial MAC schedule."""
    import numpy as np

    weight = module.op0_weight.double()
    cout, cin, kh, kw = weight.shape
    scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
    bias = -module.op1_running_mean.double()
    if getattr(module, "op0_bias", None) is not None:
        bias = bias + module.op0_bias.double()
    bias = module.op1_bias.double() + bias * scale
    weight = weight * scale[:, None, None, None]

    taps = weight.transpose(2, 3).reshape(cout, cin, 9).numpy()
    rows = np.zeros((cout, 1 + cin, 128))
    rows[:, 0, 0] = bias.numpy()
    rows[:, 1:, :9] = taps
    pieces = []
    for _ in range(2):
        exponent = np.frexp(np.abs(rows).max(axis=-1, keepdims=True))[1]
        step = np.exp2(exponent.astype(float) - 6)
        part = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + .5), 63) * step
        pieces.append(part)
        rows = rows - part
    packed = np.stack((*pieces, rows), axis=2).reshape(-1, 128)
    mask = np.ones(128)
    mask[(params['in0_d2'] - 1) % 128] = 0
    return {'weights': np.vstack((np.zeros(128), mask, packed))}
