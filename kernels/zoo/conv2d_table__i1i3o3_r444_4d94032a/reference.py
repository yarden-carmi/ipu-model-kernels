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
    r0 = aten.conv2d.default(_v(ins[1], [1, 192, 32, 32], [196608, 1024, 32, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 96, 32, 32], [98304, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 96, 32, 32])}
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

    def leading(v):
        step = np.exp2(float(np.frexp(np.max(np.abs(v)))[1]) - 6)
        return np.sign(v) * np.minimum(np.floor(np.abs(v) / step + .5), 63) * step

    w, b = weight.numpy().reshape(cout, cin, 9), bias.numpy()
    width = params['in1_d3']
    lanes = np.arange(128)
    height = params['in1_d2']
    if height * width <= 64:
        y, x = (lanes % 64) // width, lanes % width
        masks = np.array([((y + dy >= 0) & (y + dy < height) & (y < height)
                           & (x + dx >= 0) & (x + dx < width))
                          for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
        w = np.pad(w, ((0, cout % 2), (0, cin % 2), (0, 0)))
        b = np.pad(b, (0, cout % 2))
        channels = np.arange(w.shape[1])
        stagger = (channels + 1) % len(channels)
        w[1::2] = w[1::2, stagger]
        base = np.exp2(np.frexp(np.maximum(np.maximum(np.linalg.norm(w, axis=(1, 2)), np.abs(b)), 1e-30))[1] - 1)
        factors = np.arange(32, 64) / 32
        rows = []
        for o in range(0, len(b), 2):
            candidates = base[o:o+2, None] * factors
            a = w[o][None, None] / candidates[0, :, None, None, None]
            d = w[o+1][None, None] / candidates[1, None, :, None, None]
            block_exp = np.frexp(np.maximum(abs(a), abs(d)))[1] - 1

            def error(v):
                exp = np.frexp(abs(v))[1] - 1
                step = np.exp2(np.maximum(exp, block_exp - 3) - 5.)
                return np.minimum(np.floor(abs(v) / step + .5) * step,
                                  np.exp2(block_exp) * (63 / 32)) - abs(v)

            score = (np.sum(error(a)**2, axis=(-2, -1)) * candidates[0, :, None]**2
                     + np.sum(error(d)**2, axis=(-2, -1)) * candidates[1, None, :]**2)
            i, j = np.unravel_index(np.argmin(score), score.shape)
            norm = candidates[[0, 1], [i, j]]
            bv = b[o:o+2] / norm
            hi = leading(bv)
            rows.extend(np.repeat(v, 64) for v in (hi, bv - hi))
            pair = (w[o:o+2] / norm[:, None, None]).transpose(1, 2, 0)
            rows.extend((np.repeat(pair, 64, axis=-1) * masks).reshape(-1, 128))
            rows.extend(np.full(128, v) for v in norm)
        return {'weights': np.asarray(rows)}

    rows = [lanes % width != 0, lanes % width != width - 1]
    for bv, taps in zip(b, w):
        block = 14
        # Search the coefficient grid for a shared output-channel scale.
        # Restore the scale with a two-piece de-normalizer after the MACs.
        factors = np.arange(1024, 2017) / 1024
        score = np.zeros(len(factors))
        for c in range(0, cin, block):
            v = taps[c:c+block].flatten()[None, :] / factors[:, None]
            a = np.abs(v)
            expo = np.frexp(a.max(axis=1, keepdims=True))[1] - 1
            step = np.exp2(np.maximum(np.frexp(a)[1] - 1, expo - 3) - 5.)
            decoded = np.minimum(np.floor(a / step + .5) * step, np.exp2(expo) * (63 / 32))
            score += ((decoded - a)**2).sum(axis=1) * factors**2
        norm = factors[np.argmin(score)]
        bv, taps = bv / norm, taps / norm
        hi = leading(bv)
        for v in (hi, bv - hi):
            row = np.zeros(128)
            row[0] = v
            rows.append(row)
        for c in range(0, cin, block):
            v = taps[c:c+block].flatten()
            rows.append(np.pad(v, (0, 128-len(v))))
        high = leading(norm)
        rows.append(np.full(128, high))
        rows.append(np.full(128, norm - high))
    return {'weights': np.asarray(rows)}
