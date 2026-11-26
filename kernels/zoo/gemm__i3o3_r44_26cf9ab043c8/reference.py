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
    r0 = aten.conv2d.default(_v(ins[0], [1, 256, 32, 32], [262144, 1024, 32, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def _digits(rows, bits=4):
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exponent - bits)
    levels = torch.round(rows / step)
    if bits == 6:
        levels = levels.clamp(-63, 63)
    coarse = levels * step
    return torch.stack((coarse, rows - coarse), dim=-2)


def _center_direct(taps):
    # A shared sum of these activation channels lets each feature translate
    # its direct weights before rounding, then restore the offset in FP32.
    _, exp = torch.frexp(taps.abs().amax(dim=(-1, -2), keepdim=True))
    candidates = torch.ldexp(torch.arange(-63, 64, dtype=taps.dtype)[None, :, None, None],
                             exp[:, None] - 10)
    shifted = taps[:, None] - candidates
    mag = shifted.abs()
    _, e = torch.frexp(mag)
    _, scale = torch.frexp(mag.amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(mag), torch.maximum(e, scale - 3) - 6)
    limit = torch.ldexp(torch.full_like(mag, 63), scale - 6)
    rounded = torch.minimum(torch.floor(mag / step + 0.5) * step, limit).copysign(shifted)
    err = rounded - shifted
    score = err.square().sum(dim=(-1, -2)) + err.sum(dim=(-1, -2)).square()
    min_step = torch.ldexp(torch.ones_like(scale), scale - 9)
    grid = candidates / min_step
    score = score.masked_fill((grid != grid.round()).any(dim=(-1, -2)), float('inf'))
    score = score.masked_fill((4 * candidates.abs() > taps[:, None].abs()).any(dim=(-1, -2)), float('inf'))
    offset = candidates[torch.arange(taps.shape[0]), score.argmin(dim=1), 0, 0]
    return taps - offset[:, None, None], offset


def fold(module, **params):
    """Fold convolution and inference BN, then pack coarse/residual rows."""
    n, k = params['n'], params['k']
    source = getattr(module, 'weight', getattr(module, 'op0_weight', None))
    weight = source.detach().double().reshape(n, k)
    source_bias = getattr(module, 'bias', getattr(module, 'op0_bias', None))
    bias = (source_bias.detach().double().reshape(n)
            if params['bias'] and source_bias is not None else weight.new_zeros(n))
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale

    pad = torch.nn.functional.pad
    name = 'w' if params['bias'] else 'w_unbiased'
    spatial = params['in0_d2'] * params['in0_d3']
    if spatial == 64 and k % 2 == 0 and k <= 1024:
        chunks = (k + 127) // 128
        dots = pad(weight, (0, 128 * chunks - k)).reshape(n, chunks, 128)
        digits = _digits(dots)
        corrected = min(2, chunks - 1) if params['bias'] and chunks >= 3 else (0 if params['bias'] else chunks - 1)
        rows = torch.cat([digits[:, i] if i == corrected else dots[:, i:i+1]
                          for i in range(chunks)], dim=1)
    elif (spatial > 1024 and k >= 256 and k % 128 == 0 and
          (params['in0_d3'] <= 128 or params['in0_d3'] % 128 == 0)):
        taps = weight.reshape(n, k // 128, 128)
        direct, offset = _center_direct(taps[..., 109:])
        rows = _digits(pad(taps[..., :109], (0, 19)), bits=6)
        rows = torch.cat((rows, pad(direct, (109, 0)).unsqueeze(-2)), dim=-2)
        rows = torch.cat((rows.reshape(n, -1, 128), pad(offset[:, None, None], (0, 127))), dim=1)
    else:
        blocks = (k + 31) // 32
        taps = pad(weight, (0, blocks * 32 - k)).reshape(n, blocks, 32)
        rows = _digits(taps, bits=6 if spatial > 1024 and k >= 256 else 4)
        if spatial > 1024:
            corrected = 26 if k >= 128 else 22
            direct_taps = taps.clone()
            direct_taps[..., :corrected] = 0
            rows[..., corrected:] = 0
            rows = torch.cat((rows, direct_taps.unsqueeze(-2)), dim=-2)
        else:
            corrected = (22 if spatial <= 256 else 24 if k >= 256 else
                         26 if k >= 128 else 20 if spatial >= 4096 else 32)
            direct = slice(corrected, None)
            rows[..., 0, direct] = taps[..., direct]
            rows[..., 1, direct] = 0
        rows = pad(rows, (0, 96))
    rows = rows.reshape(n, -1, 128)
    if params['bias']:
        rows = torch.cat((_digits(bias[:, None].expand(-1, 128)), rows), dim=1)
    return {name: rows.reshape(-1, 128)}
