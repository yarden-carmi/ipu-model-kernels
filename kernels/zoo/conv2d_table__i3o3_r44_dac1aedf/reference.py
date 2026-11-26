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
    r0 = aten.batch_norm.default(_v(op0, [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 96, 32, 32], [98304, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch normalization and encode high/low FP8 rows."""
    import numpy as np

    w = module.op0_weight.double()
    cout, ni, kh, kw = w.shape
    cin, groups = params['cin'], params['groups']
    bias = getattr(module, 'op0_bias', None)
    bias = w.new_zeros(cout) if bias is None else bias.double()
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        w = w * scale[:, None, None, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale

    width, ow, stride = (params[k] for k in ('w', 'out0_d3', 'stride'))
    dw = groups == cin == cout and width <= 128
    pack = 128 // width * stride if dw else max(1, 128 // width * (2 - stride))
    if not dw and groups != 1:
        expanded = w.new_zeros(cout, cin, kh, kw)
        no = cout // groups
        for g in range(groups):
            expanded[g*no:(g+1)*no, g*ni:(g+1)*ni] = w[g*no:(g+1)*no]
        w = expanded
    taps = w.flatten(2).numpy()
    if dw or pack > 1:
        rows = np.zeros(((cout + pack - 1) // pack, 1 + taps.shape[1] * 9, 128))
        x = np.arange(ow)[None, :] * stride + np.arange(taps.shape[1] * 9)[:, None] % 3 - 1
        mask = (x >= 0) & (x < width)
        for c in range(cout):
            block, segment = divmod(c, pack)
            lanes = slice(segment * ow, (segment + 1) * ow)
            rows[block, 0, lanes] = bias[c].item()
            rows[block, 1:, lanes] = taps[c].reshape(-1, 1) * mask
    else:
        rows = np.concatenate((np.broadcast_to(bias.numpy()[:, None, None], (cout, 1, 128)),
                               np.pad(taps, ((0, 0), (0, 0), (0, 119)))), axis=1)
    step = np.exp2(np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 6.)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    low = rows - hi
    if dw:
        coeff = np.stack((hi, low), axis=2).reshape(-1, 128)
    elif pack > 1:
        parts = [hi[:, 0], low[:, 0]]
        for t in range(taps.shape[1] * 9):
            i = t + 1
            paired = width == 32 or t % 9 // 3 == 1
            parts.extend((hi[:, i], low[:, i]) if paired else (rows[:, i],))
        coeff = np.pad(np.stack(parts, axis=1).reshape(-1, 128), ((0, 1), (0, 0)))
    else:
        hi[:, 1:, 1:4] = rows[:, 1:, 1:4]
        coeff = np.pad(np.stack((hi, rows - hi), axis=2).reshape(-1, 128), ((0, 2), (0, 0)))
    return {'weights': coeff}
