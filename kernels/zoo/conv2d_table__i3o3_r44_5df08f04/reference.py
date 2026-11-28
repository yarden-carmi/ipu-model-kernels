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
    r0 = aten.conv2d.default(_v(ins[0], [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op0_weight, None, [1, 1], [1, 1], [1, 1], 256)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 256, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference BN and encode the horizontally masked taps in three parts."""
    import numpy as np

    weight = module.op0_weight.double()
    cout, gc, kh, kw = weight.shape
    conv_bias = getattr(module, 'op0_bias', None)
    bias = weight.new_zeros(cout) if conv_bias is None else conv_bias.double()
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    w, ow, stride, padding = (params[k] for k in ('w', 'out0_d3', 'stride', 'padding'))
    tiles = (ow + 127) // 128
    rows = np.empty((cout, tiles, 1 + gc * kh * kw, 128), dtype=np.float64)
    for tile in range(tiles):
        x = np.arange(128) % min(128, ow) + tile * 128
        ix = x[None, :] * stride + np.arange(gc * kh * kw)[:, None] % kw - padding
        rows[:, tile, 0] = bias.numpy()[:, None]
        rows[:, tile, 1:] = weight.reshape(cout, -1, 1).numpy() * ((0 <= ix) & (ix < w))

    def leading(values):
        exponent = np.frexp(np.max(np.abs(values), axis=-1, keepdims=True))[1] - 1
        step = np.exp2(exponent.astype(float) - 5)
        return np.sign(values) * np.minimum(np.floor(np.abs(values) / step + 0.5), 63) * step

    hi = leading(rows)
    remainder = rows - hi
    mid = leading(remainder)
    parts = np.stack((hi, mid, remainder - mid), axis=-2)
    ir = (params['in0_d2'] * w + 127) // 128
    if (stride == 1 and w == 64 and gc == 1 and ir >= 3
            and params['in0_d2'] % 2 == 0 and params['in0_d2'] == params['out0_d2']):
        scalar = np.zeros_like(rows[:, :, 0])
        scalar[:, :, 0] = remainder[:, :, 0, 0]
        scalar[:, :, 1] = remainder[:, :, 5, 0]
        packed = [hi[:, :, 0], scalar]
        for t in range(1, 10):
            packed.append(hi[:, :, t])
            if t != 5:
                packed.append(remainder[:, :, t])
        return {'weights': np.pad(np.stack(packed, axis=2).reshape(-1, 128), ((0, 1), (0, 0)))}
    if (stride == 2 and gc == 1 and params['in0_d2'] * w % 128 == 0
            and params['out0_d2'] * ow % 128 == 0 and ow in (16, 32, 64)):
        values = weight.reshape(cout, 9).numpy()
        high = leading(values)
        packed = np.zeros((cout, 2, 128), dtype=np.float64)
        packed[:, 0, :9] = high
        packed[:, 1, :9] = values - high
        return {'weights': np.concatenate((parts[:, 0, 0], packed), axis=1).reshape(-1, 128)}
    direct128 = stride == 1 and w == 128 and gc == 1 and ir >= 3 and params['in0_d2'] * w % 128 == 0 and params['in0_d2'] == params['out0_d2']
    if (stride == 1 and w == 64 and gc == 1) or direct128:
        scalar = np.zeros_like(rows[:, :, 0])
        scalar[:, :, :2] = remainder[:, :, [5, 8], 0]
        packed = [hi[:, :, 0], mid[:, :, 0]]
        for t in range(1, 10):
            packed.append(hi[:, :, t])
            if t != 8:
                packed.append(scalar if t == 5 else remainder[:, :, t])
        return {'weights': np.stack(packed, axis=2).reshape(-1, 128)}
    if stride == 2 and w == 256 and params['groups'] == 1 and gc <= 3:
        values = rows[:, 0, 1:, 1].reshape(cout, gc, kh * kw)
        hi_values = leading(values)
        packed = np.zeros((cout, gc, 2, 128), dtype=np.float64)
        packed[:, :, 0, :kh * kw] = hi_values
        packed[:, :, 1, :kh * kw] = values - hi_values
        return {'weights': np.concatenate((parts[:, 0, 0], packed.reshape(cout, 2 * gc, 128)), axis=1).reshape(-1, 128)}
    taps = np.stack((hi[:, :, 1:], remainder[:, :, 1:]), axis=-2)
    if stride == 1 and w in (8, 16, 32) and params['groups'] == 1 and gc > 1:
        sides = taps.reshape(cout, tiles, gc, 9, 2, 128)[:, :, :, [0, 2, 3, 5, 6, 8]]
        centers = weight.reshape(cout, gc, 9).numpy()[:, :, [1, 7, 4]]
        center_hi = leading(centers)
        scalar = np.zeros((cout, tiles, gc, 2, 128), dtype=np.float64)
        scalar[:, :, :, 0, :3] = center_hi[:, None]
        scalar[:, :, :, 1, :3] = (centers - center_hi)[:, None]
        taps = np.concatenate((sides.reshape(cout, tiles, gc, 12, 128), scalar), axis=3)
    packed = np.concatenate((
        parts[:, :, 0].reshape(cout, tiles, 3, 128),
        taps.reshape(cout, tiles, -1, 128),
    ), axis=2).reshape(-1, 128)
    if stride == 1 and w <= 128 and gc > 1:
        packed = np.pad(packed, ((0, 1), (0, 0)))
    return {'weights': packed}
