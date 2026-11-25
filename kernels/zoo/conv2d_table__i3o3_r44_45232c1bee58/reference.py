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
    r0 = aten.conv2d.default(_v(ins[0], [1, 240, 14, 14], [47040, 196, 14, 1], 0), module.op0_weight, None, [1, 1], [2, 2], [1, 1], 240)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 240, 14, 14], [47040, 196, 14, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.hardswish_.default(_v(op1, [1, 240, 14, 14], [47040, 196, 14, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 240, 14, 14])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch norm and store three precision components per coefficient."""
    import numpy as np

    weight = module.op0_weight.double()
    b = getattr(module, 'op0_bias', None)
    b = weight.new_zeros(weight.shape[0]) if b is None else b.double()
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        b = module.op1_bias.double() + (b - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]
    values = np.concatenate((b.numpy()[:, None], weight.flatten(1).numpy()), axis=1)
    parts = []
    for _ in range(2):
        step = np.exp2(np.frexp(np.abs(values))[1].astype(float) - 6)
        digit = np.clip(np.rint(values / step), -63, 63) * step
        parts.append(digit)
        values = values - digit
    parts.append(values)
    coeff = np.stack(parts, axis=-1)
    if params['stride'] == 1 and params['w'] == params['out0_d3'] and params['h'] == params['out0_d2']:
        h, w = params['h'], params['w']
        fit = min(h, 128 // w)
        pack = max(fit if h % fit == 0 else 1, h // 2 if h % 2 == 0 and h > fit and h * w <= 256 else 1)
        span = pack * w
        lanes = np.arange(128)
        masks = []
        for ky in range(params['kh']):
            for kx in range(params['kw']):
                dx = kx - params['padding']
                off = ((ky - params['padding']) * w + dx) % span
                good = (lanes < span) & (lanes % w + dx >= 0) & (lanes % w + dx < w)
                masks.append(np.stack((good & (lanes + off < span), good & (lanes + off >= span))))
        masks = np.asarray(masks)
        c = coeff[:, 1:].reshape(weight.shape[0], weight.shape[1], len(masks), 1, 3, 1)
        products = (c * masks[None, None, :, :, None, :]).reshape(weight.shape[0], -1, 128)
        bias_rows = np.repeat(coeff[:, :1].reshape(-1, 3, 1), 128, axis=2)
        return {'weights': np.concatenate((bias_rows, products), axis=1).reshape(-1, 128)}
    return {'weights': np.repeat(coeff.reshape(-1, 1), 128, axis=1)}
