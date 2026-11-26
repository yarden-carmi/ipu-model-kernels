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
    r0 = aten.conv2d.default(_v(ins[0], [1, 384, 32, 32], [393216, 1024, 32, 1], 0), module.op0_weight, None, [2, 2], [1, 1], [1, 1], 384)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 384, 16, 16], [98304, 256, 16, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 384, 16, 16], [98304, 256, 16, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 384, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference BN, mask horizontal padding, and split coefficients."""
    import numpy as np

    weight = module.op0_weight.double()
    cout, gc, kh, kw = weight.shape
    bias = getattr(module, 'op0_bias', None)
    bias = weight.new_zeros(cout) if bias is None else bias.double()
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    w, padding = (params[k] for k in ('w', 'padding'))
    tiles = (w + 127) // 128
    rows = np.empty((cout, tiles, 1 + gc * kh * kw, 128), dtype=np.float64)
    for tile in range(tiles):
        x = np.arange(128) % min(128, w) + tile * 128
        ix = x[None, :] + np.arange(gc * kh * kw)[:, None] % kw - padding
        rows[:, tile, 0] = bias.numpy()[:, None]
        rows[:, tile, 1:] = weight.reshape(cout, -1, 1).numpy() * ((0 <= ix) & (ix < w))

    def leading(values):
        exponent = np.frexp(np.max(np.abs(values), axis=-1, keepdims=True))[1] - 1
        step = np.exp2(exponent.astype(float) - 5)
        return np.sign(values) * np.minimum(np.floor(np.abs(values) / step + 0.5), 63) * step

    hi = leading(rows)
    remainder = rows - hi
    mid = leading(remainder)
    return {'weights': np.stack((hi, mid, remainder - mid), axis=-2).reshape(-1, 128)}
