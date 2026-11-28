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
    r0 = aten.conv2d.default(_v(ins[1], [1, 256, 16, 16], [65536, 256, 16, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 128, 16, 16], [32768, 256, 16, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 128, 16, 16], [32768, 256, 16, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 128, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    import numpy as np
    w = module.op0_weight.double()
    cout, ni, kh, kw = w.shape
    cin, groups = params['cin'], params['groups']
    bias = getattr(module, 'op0_bias', None)
    bias = w.new_zeros(cout) if bias is None else bias.double()
    scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
    w = w * scale[:, None, None, None]
    bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
    if groups == cin == cout:
        taps = w[:, 0].flatten(1).T
    else:
        if groups != 1:
            expanded = w.new_zeros(cout, cin, kh, kw)
            no = cout // groups
            for g in range(groups):
                expanded[g*no:(g+1)*no, g*ni:(g+1)*ni] = w[g*no:(g+1)*no]
            w = expanded
        taps = w.permute(2, 3, 1, 0).reshape(-1, cout)
    chunks = (cout + 127) // 128
    rows = torch.cat((bias[None], taps)).numpy()
    rows = np.pad(rows, ((0, 0), (0, chunks*128 - cout)))
    rows = rows.reshape(-1, chunks, 128).transpose(1, 0, 2)
    area = params['in1_d2'] * params['in1_d3']
    balance = area == 256 and not groups == cin == cout
    if balance:
        # Scale each output channel before folding so single-row weights use
        # more of the shared exponent's precision. The epilogue undoes it.
        single_rows = []
        for t in range(kh * kw):
            for c in range((cin + 127)//128):
                n = min(128, cin - 128*c)
                single = (111*n)//128
                start = 1 + t*cin + 128*c + (0 if t % kw == 0 else n-single)
                single_rows.extend(range(start, start+single))
        magnitude = np.abs(rows[:, single_rows])
        peaks = np.max(magnitude, axis=1, keepdims=True)
        gain = np.maximum(1/8, np.ceil(64 * peaks / np.maximum(peaks.max(axis=-1, keepdims=True), 1e-300)) / 64)
        options = np.arange(64, 513) / 512
        for b in range(chunks):
            a = magnitude[b]
            for _ in range(4):
                # Score representable gains on the E2 grid without raising
                # the current exponent of any single-weight row.
                scale = np.exp2(np.frexp((a / gain[b]).max(axis=1))[1] - 1)
                scores = []
                for candidates in np.array_split(options, 16):
                    scaled = a[:, :, None] / candidates
                    stride = scale[:, None, None] / 32
                    stride = np.where(scaled >= scale[:, None, None], stride,
                                       np.where(scaled >= scale[:, None, None]/2, stride/2, stride/4))
                    delta = np.minimum(np.floor(scaled / stride + 0.5) * stride,
                                       scale[:, None, None] * (63/32)) * candidates - a[:, :, None]
                    error = np.sum(delta**2, axis=0)
                    error[np.any(scaled >= 2*scale[:, None, None], axis=0)] = np.inf
                    scores.append(error)
                error = np.concatenate(scores, axis=-1)
                gain[b, 0] = options[np.argmin(error, axis=1)]
        rows = rows / gain
    step = np.exp2(np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 6.)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    if groups != cin or groups != cout:
        parts = [hi[:, :1], rows[:, :1] - hi[:, :1]]
        for t in range(kh * kw):
            for c in range((cin + 127)//128):
                n = min(128, cin - 128*c)
                single = (15*n)//32 if area >= 512 else (111*n)//128 if balance else n//2
                start = 1 + t*cin + 128*c
                if t % kw == 0 or area >= 512:
                    parts.append(rows[:, start:start+single])
                    sl = slice(start+single, start+n)
                    parts.append(np.stack((hi[:, sl], rows[:, sl] - hi[:, sl]), axis=2).reshape(chunks, -1, 128))
                else:
                    sl = slice(start, start+n-single)
                    parts.append(np.stack((hi[:, sl], rows[:, sl] - hi[:, sl]), axis=2).reshape(chunks, -1, 128))
                    parts.append(rows[:, start+n-single:start+n])
        if balance:
            grid = np.exp2(np.frexp(gain.max(axis=-1, keepdims=True))[1] - 1) / 32
            high = np.minimum(np.floor(gain / grid + 0.5), 63) * grid
            parts.extend((high, gain - high))
        return {'weights': np.concatenate(parts, axis=1).reshape(-1, 128)}
    return {'weights': np.stack((hi, rows - hi), axis=-2).reshape(-1, 128)}
