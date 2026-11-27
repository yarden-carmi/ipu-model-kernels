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
    r0 = aten.conv2d.default(_v(ins[0], [1, 144, 14, 14], [28224, 196, 14, 1], 0), module.op0_weight, None, [1, 1], [2, 2], [1, 1], 144)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 144, 14, 14], [28224, 196, 14, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.hardswish_.default(_v(op1, [1, 144, 14, 14], [28224, 196, 14, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 144, 14, 14])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch normalization and split coefficients into three NX8 rows."""
    import numpy as np

    weight = module.op0_weight.double()
    channels = weight.shape[0]
    conv_bias = getattr(module, "op0_bias", None)
    bias = weight.new_zeros(channels) if conv_bias is None else conv_bias.double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    taps = weight[:, 0].flatten(1).T
    chunks = (channels + 127) // 128
    rows = torch.cat((bias[None], taps)).numpy()
    rows = np.pad(rows, ((0, 0), (0, chunks * 128 - channels)))
    rows = rows.reshape(-1, chunks, 128).transpose(1, 0, 2)
    step = np.exp2(np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 6.)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    rem = rows - hi
    step2 = np.exp2(np.frexp(np.max(np.abs(rem), axis=-1, keepdims=True))[1] - 6.)
    mid = np.sign(rem) * np.minimum(np.floor(np.abs(rem) / step2 + 0.5), 63) * step2
    return {'weights': np.stack((hi, mid, rem - mid), axis=-2).reshape(-1, 128)}
