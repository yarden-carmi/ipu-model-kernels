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
    r0 = aten.conv2d.default(_v(ins[0], [1, 32, 128, 128], [524288, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 128, 128, 128], [2097152, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 128, 128, 128], [2097152, 16384, 128, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 128, 128, 128])}
# ---- end of the frozen reference ----


def _digits(rows, bits):
    """Split row-scaled coefficients into a coarse term and a residual."""
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - bits)
    coarse = torch.round(rows / step) * step
    return torch.stack((coarse, rows - coarse), dim=-2)


def _compensated(weight, groups, width, mantissa):
    """Write each tap as a main coefficient plus a group-shared offset."""
    n = weight.shape[0]
    w = weight.reshape(n, groups, width, 1)
    _, e = torch.frexp(w.abs().amax(dim=(1, 2), keepdim=True))
    scale = torch.ldexp(torch.ones_like(e, dtype=weight.dtype), e - 1)
    quantum = scale / (1 << mantissa)
    grid = torch.arange(-64, 65, dtype=weight.dtype, device=weight.device)
    delta = quantum * grid / 64
    v = (w - delta).abs()
    if mantissa == 6:
        step = quantum
    else:
        _, ev = torch.frexp(v)
        step = torch.maximum(quantum / 4, torch.ldexp(torch.ones_like(v), ev - 6))
    error = (torch.minimum(torch.round(v / step) * step, 2 * scale - quantum) - v).abs()
    loss = error.amax(dim=2, keepdim=True).square() + error.square().mean(dim=2, keepdim=True) / 4
    loss = loss + delta.square() / 4096
    correction = delta.expand(n, groups, 1, -1).gather(-1, loss.argmin(dim=-1, keepdim=True))
    rows = weight.new_zeros(n, 2, 128)
    rows[:, 0, :groups * width] = (w - correction).reshape(n, -1)
    rows[:, 0, 127] = scale.flatten()
    rows[:, 1, :groups] = correction.reshape(n, groups)
    return rows


def fold(module, **params):
    n, k = params['n'], params['k']
    source = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    weight = source.double().reshape(n, k)
    source_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weight.new_zeros(n) if source_bias is None else source_bias.double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None]
        bias = (bias - module.op1_running_mean.double()) * scale + module.op1_bias.double()
    if not params['bias']:
        bias = weight.new_zeros(n)

    if 16 <= k <= 96 and k % 16 == 0:
        width = 3 if k == 16 else 2
        groups = 5 if k == 16 else min(24, k * 3 // 8)
        prefix = k - groups * width
        bits = 6 if k == 16 else 4
        blocks = (prefix + 31) // 32
        rows = weight.new_zeros(n, blocks, 128)
        rows[:, :, :32] = torch.nn.functional.pad(weight[:, :prefix], (0, blocks * 32 - prefix)).reshape(n, blocks, 32)
        if k <= 32:
            rows[:, 0, 127] = bias
        parts = [_digits(rows, bits).reshape(n, -1, 128),
                 _compensated(weight[:, prefix:], groups, width, 6 if k == 16 else 5)]
        if k > 32:
            parts.insert(0, _digits(bias[:, None].expand(n, 128), bits))
        packed = torch.cat(parts, dim=1)
        return {'coeff': torch.nn.functional.pad(packed.reshape(-1, 128), (0, 0, 0, 1))}

    # Give the single-digit taps their own scale, separate from the paired taps.
    short = k <= 16
    bits = 6 if short else 4
    singles = k // 4 if short else (3 if k <= 32 else 0)
    cut = k - singles if short else (k // 4 if singles else k)
    paired = k - singles
    prefix = torch.cat((weight[:, :cut], weight[:, cut + singles:]), dim=1)
    blocks = (paired + 31) // 32
    rows = weight.new_zeros(n, blocks, 128)
    rows[:, :, :32] = torch.nn.functional.pad(prefix, (0, blocks * 32 - paired)).reshape(n, blocks, 32)
    if k <= 32:
        rows[:, 0, 127] = bias
    packed = _digits(rows, bits).reshape(n, -1, 128)
    if k > 32:
        packed = torch.cat((_digits(bias[:, None].expand(n, 128), bits), packed), dim=1)
    if singles:
        tail = weight.new_zeros(n, 1, 128)
        tail[:, 0, :singles] = weight[:, cut:cut + singles]
        packed = torch.cat((packed, tail), dim=1)
    return {'coeff': torch.nn.functional.pad(packed.reshape(-1, 128), (0, 0, 0, 1))}
