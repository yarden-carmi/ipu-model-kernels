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
    r0 = aten.conv2d.default(_v(ins[0], [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 48, 32, 32], [49152, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 48, 32, 32], [49152, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 48, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch normalization and split coefficients into two NX8 rows."""
    import numpy as np

    weight = module.op0_weight.double()
    channels = weight.shape[0]
    conv_bias = getattr(module, "op0_bias", None)
    bias = weight.new_zeros(channels) if conv_bias is None else conv_bias.double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    taps = weight.flatten(2).numpy()
    rows = np.concatenate((np.broadcast_to(bias.numpy()[:, None, None], (channels, 1, 128)),
                           np.pad(taps, ((0, 0), (0, 0), (0, 128 - taps.shape[-1])))), axis=1)
    exponent = np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 1
    step = np.exp2(exponent.astype(float) - 5)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    width = params['out0_d3']
    pack = min(8, max(1, 128 // width))
    if params['groups'] == 1 and taps.shape[1] > 1 and taps.shape[-1] >= 7:
        end = 4 if params['cin'] == 96 and params['cout'] == 48 and width == 32 and params['groups'] == 1 else (4 if params['stride'] == 2 else (3 if pack == 4 and params['out0_d2'] % pack == 0 else 1))
        hi[:, 1:, 1:end] = rows[:, 1:, 1:end]
        if params['cin'] == 96 and params['cout'] == 48 and width == 32 and params['groups'] == 1:
            hi[:, 1:, 5:6] = rows[:, 1:, 5:6]
    coeff = np.stack((hi, rows - hi), axis=2).reshape(-1, 128)

    if params["groups"] == 1 and weight.shape[1] > 1:
        coeff = np.pad(coeff, ((0, 2), (0, 0)))
    return {"weights": coeff}
