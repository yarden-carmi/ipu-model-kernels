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
    r0 = aten.conv2d.default(_v(ins[0], [1, 160, 8, 8], [10240, 64, 8, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 640, 8, 8], [40960, 64, 8, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 640, 8, 8], [40960, 64, 8, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 640, 8, 8])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold batch normalization and tile coefficients by output channel."""
    n, k = params["n"], params["k"]
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    if getattr(module, "op0_bias", None) is not None:
        bias = bias + module.op0_bias.double() * scale
    padded = ((n + 127) // 128) * 128
    rows = weight.new_zeros((k + 1, padded))
    if params["bias"]:
        rows[0, :n] = bias
    rows[1:, :n] = weight.T
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1).reshape(-1, 128)
    # Store the coarse value and residual separately to reduce FP8 error.
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 4)
    coarse = torch.round(rows / step) * step
    pairs = torch.stack((coarse, rows - coarse), dim=1)
    if n <= 64 and k <= 64 and k % 2 == 0:
        taps = rows[1:, :64].reshape(-1, 128)
        _, exp = torch.frexp(taps.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(exp, dtype=taps.dtype), exp - 4)
        high = torch.round(taps / step) * step
        if k == 16:
            return {"coeff": torch.cat((pairs[0], torch.stack((high[:6], taps[:6] - high[:6]), dim=1).flatten(0, 1), taps[6:]))}
        return {"coeff": torch.cat((pairs[0], torch.stack((high, taps - high), dim=1).flatten(0, 1)))}
    width, height = params["in0_d3"], params["in0_d2"]
    limit = min(height, 128 // width)
    pixels = width * (1 if height % limit else limit)
    if k % 16 == 0 and pixels % 8 == 0:
        if (k == 64 and n > 64) or (k in (96, 160) and n > 128 and n % 128 == 0):
            group_size = 80 if k == 160 else 8
            tiles = []
            for block in range(padded // 128):
                start = block * (k + 1)
                taps = rows[start + 1:start + k + 1]
                shifted, offset = _center_taps(taps.reshape(-1, group_size, 128))
                tiles.append(torch.cat((rows[start:start + 1], shifted, offset)))
            return {"coeff": torch.cat(tiles)}
        if k == 32 and 64 < n <= 128:
            first, first_offset = _center_taps(rows[1:9].reshape(2, 4, 128))
            last, last_offset = _center_taps(rows[9:].reshape(4, 6, 128))
            return {"coeff": torch.cat((rows[:1], first, last, first_offset, last_offset))}
        # Keep residuals for most taps; encode the rest directly.
        index = torch.arange(rows.shape[0], device=rows.device) % (k + 1)
        single = (index > 0) & ((index - 1) % 16 >= (16 if n <= 64 else (8 if k >= 160 else 11 if k == 32 else 12)))
        if k == 32 and n > 64:
            single |= (index - 1) % 32 == 26
        if k == 96 and n > 64:
            single = (index > 0) & ((index - 1) % 16 < 4)
        pairs[single, 0] = rows[single]
        return {"coeff": pairs[torch.stack((torch.ones_like(single), ~single), dim=1)]}
    return {"coeff": pairs.reshape(-1, 128)}


def _center_taps(taps):
    """Fit a shared offset to the FP8 rounding grid of a group of coefficient rows."""
    _, ex = torch.frexp(taps.abs().amax(dim=2, keepdim=True))
    grid = torch.ldexp(torch.ones_like(taps[:, :1, :1]), ex - 6)
    candidates = grid.amax(dim=1, keepdim=True) * torch.linspace(-3, 3, 769, dtype=taps.dtype, device=taps.device)
    shifted = taps.unsqueeze(-1) - candidates.unsqueeze(1)
    def round_row(values, row_ex):
        _, value_ex = torch.frexp(values.abs())
        step = torch.ldexp(torch.ones_like(values), torch.maximum(value_ex, row_ex - 2) - 6)
        top = torch.ldexp(torch.full_like(row_ex, 63, dtype=values.dtype), row_ex - 6)
        return torch.minimum((values.abs() / step + 0.5).floor() * step, top) * values.sign()

    row_ex = torch.frexp(taps.abs().amax(dim=2, keepdim=True)).exponent
    offset = taps[:, 0] * 0
    for iteration in range(4):
        choices = candidates.expand(-1, 128, -1)
        if iteration:
            offset_ex = torch.frexp(offset.abs().amax(dim=1, keepdim=True)).exponent
            choices = round_row(choices, offset_ex.unsqueeze(-1))
        shifted = taps.unsqueeze(-1) - choices.unsqueeze(1)
        err = shifted - round_row(shifted, row_ex.unsqueeze(-1))
        cost = (err.square().sum(dim=1) + err.sum(dim=1).square() * 0.5
                + choices.square() * 0.004 + err.square().amax(dim=1) * 0.5)
        offset = choices.gather(-1, cost.argmin(dim=-1, keepdim=True)).squeeze(-1)
        row_ex = torch.frexp((taps - offset[:, None]).abs().amax(dim=2, keepdim=True)).exponent
    return (taps - offset[:, None]).reshape(-1, 128), offset
