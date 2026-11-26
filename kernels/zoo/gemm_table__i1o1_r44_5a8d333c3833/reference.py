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
    r0 = aten.conv2d.default(_v(ins[0], [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 384, 32, 32], [393216, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 384, 32, 32], [393216, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 384, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch normalization; keep a residual digit per tap."""
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
        bias = torch.zeros_like(bias)
    rows = torch.nn.functional.pad(torch.cat((bias[None], weight.T)), (0, (-n) % 128))
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    b = rows[:, :1]
    _, exponent = torch.frexp(b.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=b.dtype), exponent - 6)
    hi = (b / step).round().clamp(-63, 63) * step
    g = 2 if k <= 32 else 5 if k <= 64 else 8
    w = rows[:, 1:]
    paired = 16 < k <= 64 and params['m'] % 2 == 0
    groups = min(k // g, 12 + int(paired and n <= 128) if k <= 32 else 32) if 16 < k <= 128 else 0
    pieces = [hi, b - hi]
    _, re = torch.frexp(w.abs().amax(dim=-1, keepdim=True))
    _, ee = torch.frexp(w.abs())
    if k <= 16:
        grid = torch.ldexp(torch.ones_like(w), re - 6)
    else:
        grid = torch.ldexp(torch.ones_like(w), torch.maximum(ee - 1, re - 3) - 5)
    if k == 32:
        starts = [16 * block + i*g for block in range(2) for i in range(7 if block == 0 and groups == 13 else 6)]
    elif k == 64:
        starts = [16 * block + offset for block in range(4) for offset in (0, 5, 11)]
    else:
        starts = [j*g for j in range(groups)]
    cursor = 0
    for j in starts:
        if cursor != j:
            pieces.append(w[:, cursor:j])
        a = w[:, j:j+g]
        d = grid[:, j:j+g]
        largest = d.amax(dim=1, keepdim=True)
        phase = torch.arange(-96, 97, dtype=w.dtype, device=w.device).reshape(1, -1, 1) / 64
        cand = phase * largest
        cand = cand.expand(-1, -1, 128)
        _, se = torch.frexp(largest.amax(dim=-1, keepdim=True))
        se = se - 1
        _, ce = torch.frexp(cand.abs())
        cs = torch.ldexp(torch.ones_like(cand), torch.maximum(ce - 1, se - 3) - 5)
        cc = torch.ldexp(torch.ones_like(cand), se - 6) * 63
        cand = ((cand / cs).round() * cs).clamp(-cc, cc)
        z = a[:, None] - cand[:, :, None]
        _, ze = torch.frexp(z.abs())
        r = re[:, None, j:j+g]
        step = torch.ldexp(torch.ones_like(z), torch.maximum(ze - 1, r - 3) - 5)
        cap = torch.ldexp(torch.ones_like(z), r - 6) * 63
        rounded = ((z / step).round() * step).clamp(-cap, cap)
        error = (z - rounded).square()
        score = error.sum(dim=2) + (error.amax(dim=2) / 2 if g >= 5 else 0) + cand.square() / 512
        shared = cand.gather(1, score.argmin(dim=1, keepdim=True))
        pieces.extend((shared, a - shared))
        cursor = j + g
    split = k if k <= 16 else 0
    for j in range(split):
        a = w[:, j:j+1]
        d = grid[:, j:j+1]
        h = (a / d).round().clamp(-63, 63) * d
        pieces.extend((h, a - h))
    pieces.append(w[:, cursor+split:])
    packed = torch.cat(pieces, dim=1).reshape(-1, 128)
    if n > 128 and k <= 128:
        packed = torch.nn.functional.pad(packed, (0, 0, 0, 1))
    return {'coeff': packed}
