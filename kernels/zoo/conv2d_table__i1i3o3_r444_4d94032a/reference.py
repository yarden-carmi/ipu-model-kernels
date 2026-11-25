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


def _old_fold(module, **params):
    import numpy as np

    weight = getattr(module, "op0_weight", getattr(module, "weight", None)).double()
    channels = weight.shape[0]
    groups = params["groups"]
    bias = getattr(module, "op0_bias", getattr(module, "bias", None))
    bias = weight.new_zeros(channels) if bias is None else bias.double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]
    if groups == 1:
        # Per output chunk: split bias, tap-major weights, then a final
        # prefetch row. Retain residuals selectively: small planes gain more
        # from skipping padding and can afford more residual rows.
        cin = weight.shape[1]
        chunks = (channels + 127) // 128
        w = np.zeros((9, cin, chunks * 128))
        w[:, :, :channels] = weight.permute(2, 3, 1, 0).reshape(9, cin, channels).numpy()
        b = np.zeros(chunks * 128)
        b[:channels] = bias.numpy()
        w = w.reshape(9, cin, chunks, 128).transpose(2, 0, 1, 3)
        b = b.reshape(chunks, 128)

        def split(rows):
            exponent = np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 1
            step = np.exp2(exponent.astype(float) - 5)
            hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
            return hi, rows - hi

        bh, bl = split(b)
        wh, wl = split(w.reshape(chunks, 9 * cin, 128))
        out = []
        for o in range(chunks):
            out.append(bh[o][None])
            out.append(bl[o][None])
            for t in range(9):
                s = slice(t * cin, (t + 1) * cin)
                if cin % 16 == 0 and params['h'] * params['w'] >= 512 and t in (1, 7):
                    for c in range(cin):
                        out.append(np.stack((wh[o, t * cin + c], wl[o, t * cin + c]))
                                   if c % 2 == 0 else w[o, t, c:c+1])
                elif t in (0, 8):
                    out.append(w[o, t])
                else:
                    pair = np.stack((wh[o, s], wl[o, s]), axis=1)
                    if t in (2, 6) and cin % 16 == 0 and params['h'] * params['w'] < 512:
                        for c in range(0, cin, 128):
                            end = min(c + 128, cin)
                            n = (end - c) // 16 * 6
                            out.append(pair[c:end-n].reshape(-1, 128))
                            out.append(w[o, t, end-n:end])
                    else:
                        out.append(pair.reshape(-1, 128))
            out.append(bh[o][None])
        return {"weights": np.concatenate(out, 0)}
    if groups != params["cin"] or params["cin"] != channels:
        raise ValueError("requires depthwise convolution with channel multiplier one")
    rows = torch.cat((bias[None], weight[:, 0].reshape(channels, 9).T)).numpy()
    chunks = (channels + 127) // 128
    rows = np.pad(rows, ((0, 0), (0, 128 * chunks - channels)))
    rows = rows.reshape(10, chunks, 128).transpose(1, 0, 2)
    # Use two NX8 rows so folding does not discard the leading row's residual.
    exponent = np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 1
    step = np.exp2(exponent.astype(float) - 5)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    frames = np.stack((hi, rows - hi), axis=2).reshape(-1, 128)
    return {"weights": np.pad(frames, ((0, 1), (0, 0)))}


def fold(module, **params):
    import numpy as np

    weight = getattr(module, "op0_weight", getattr(module, "weight", None)).double()
    channels, gc = weight.shape[:2]
    bias = getattr(module, "op0_bias", getattr(module, "bias", None))
    bias = weight.new_zeros(channels) if bias is None else bias.double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    def leading(values):
        exponent = np.frexp(np.max(np.abs(values)))[1] - 1
        step = np.exp2(float(exponent) - 5)
        return np.sign(values) * np.minimum(np.floor(np.abs(values) / step + 0.5), 63) * step

    area = params['h'] * params['w']
    if area <= 64:
        width, height = params['in1_d3'], params['in1_d2']
        pos = np.arange(128) % 64
        y, x = pos // width, pos % width
        masks = [((y < height) & (y + dy >= 0) & (y + dy < height)
                  & (x + dx >= 0) & (x + dx < width))
                 for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
        rows = [np.arange(128) < 64, np.arange(128) >= 64]
        ocg = channels // params['groups']
        w = weight.reshape(channels, gc, 9).numpy()
        b = bias.numpy()
        norm = np.exp2(np.frexp(np.maximum(np.maximum(np.linalg.norm(w, axis=(1, 2)), np.abs(b)), 1e-30))[1] - 1)
        w = w / norm[:, None, None]
        b = b / norm
        for g in range(params['groups']):
            end = (g + 1) * ocg
            for o in range(g * ocg, end, 2):
                pair = slice(o, min(o + 2, end))
                bv = np.pad(b[pair], (0, 2 - len(b[pair])))
                hi = leading(bv)
                rows.extend(np.repeat(v, 64) for v in (hi, bv - hi))
                for c in range(gc):
                    for t in range(9):
                        v = w[pair, c, t]
                        v = np.pad(v, (0, 2 - len(v)))
                        hi = leading(v)
                        coeff = (v,) if t == 4 else (hi, v - hi)
                        rows.extend(np.repeat(a, 64) * masks[t] for a in coeff)
                for j in range(2):
                    rows.append(np.full(128, norm[o+j] if o+j < end else 1))
        rows.append(np.zeros(128))
        return {"weights": np.asarray(rows)}
    big = area >= 512
    block = 13 if big else 3
    rows = np.zeros((2 + channels * (2 + 2 * ((gc + block - 1) // block)), 128))
    width = params['in1_d3']
    columns = np.arange(128) % width
    rows[0] = columns != 0
    rows[1] = columns != width - 1
    idx = 2
    for b, taps in zip(bias.numpy(), weight.reshape(channels, gc, 9).numpy()):
        hi = leading(b)
        rows[idx:idx + 2, 0] = hi, b - hi
        idx += 2
        for start in range(0, gc, block):
            values = taps[start:start + block]
            E = np.frexp(np.max(np.abs(values)))[1] - 1
            step = np.exp2(float(E) - 6)
            hi = np.sign(values) * np.minimum(np.floor(np.abs(values) / step + 0.5), 127) * step
            coeff, low = [], []
            for c, vals in enumerate(values):
                for t, v in enumerate(vals):
                    if (big and t != 8) or (not big and (c + t + 1) % 3 == 0):
                        coeff.append(hi[c, t])
                        low.append(v - hi[c, t])
                    else:
                        coeff.append(v)
            rows[idx, :len(coeff)] = coeff
            rows[idx + 1, :len(low)] = low
            idx += 2
    return {"weights": rows}
