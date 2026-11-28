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
        compact = (weight.shape[2:] == (3, 3) and params['stride'] == 1
                   and params['padding'] == 1 and params['in0_d3'] == width == 32
                   and params['out0_d2'] % pack == 0)
        end = (5 if taps.shape[1] > 4 else 1) if params['stride'] == 2 else (3 if pack == 4 and params['out0_d2'] % pack == 0 else 1)
        if compact:
            # Stream rows in load order; neighboring taps share an exponent.
            parts = np.zeros((channels, taps.shape[1], 7, 128))
            pair = taps[:, :, [8, 6]]
            unit = np.exp2(np.frexp(np.max(np.abs(pair), axis=-1))[1].astype(float) - 7)
            first = np.sign(pair[:, :, 0]) * np.minimum(np.floor(np.abs(pair[:, :, 0]) / unit + 0.5), 127) * unit
            parts[:, :, 0, :2] = taps[:, :, [0, 2]]
            parts[:, :, 1, 0] = taps[:, :, 1]
            parts[:, :, 2, :2] = taps[:, :, [3, 5]]
            parts[:, :, 3, 0] = taps[:, :, 4]
            parts[:, :, 4, 0] = taps[:, :, 6]
            parts[:, :, 4, 1] = first
            parts[:, :, 5, 0] = taps[:, :, 7]
            parts[:, :, 6, 0] = taps[:, :, 8] - first
            bias_rows = np.stack((hi[:, 0], rows[:, 0] - hi[:, 0]), axis=1)
            streamed = [bias_rows]
            for c in range(taps.shape[1]):
                block = parts[:, c]
                phase = (c - taps.shape[1]) % 4 if c >= taps.shape[1] % 4 else -1
                if phase >= 0:
                    pair = taps[:, c, [0, 2]]
                    unit = np.exp2(np.frexp(np.max(np.abs(pair), axis=-1))[1].astype(float) - 7)
                    first = np.sign(pair[:, 0]) * np.minimum(np.floor(np.abs(pair[:, 0]) / unit + 0.5), 127) * unit
                    residual = np.zeros((channels, 1, 128))
                    residual[:, 0, 0] = pair[:, 0] - first
                    block[:, 0, 0] = first
                    if phase != 0:
                        block[:, 4, 1] = taps[:, c, 8]
                        block = block[:, :-1]
                    streamed.extend((block[:, :1], residual, block[:, 1:]))
                else:
                    streamed.append(block)
            coeff = np.concatenate(streamed, axis=1)
            return {"compact_weights": np.pad(coeff.reshape(-1, 128), ((0, 2), (0, 0))),
                    "weights": np.zeros((1, 128))}
        hi[:, 1:, 1:end] = rows[:, 1:, 1:end]
    coeff = np.stack((hi, rows - hi), axis=2).reshape(-1, 128)

    if params["groups"] == 1 and weight.shape[1] > 1:
        coeff = np.pad(coeff, ((0, 2), (0, 0)))
    return {"weights": coeff, "compact_weights": np.zeros((1, 128))}
