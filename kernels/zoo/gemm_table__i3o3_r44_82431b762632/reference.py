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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 256, 64, 64])}
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

    blocks = (k + 31) // 32
    rows = weight.new_zeros(n, 1 + blocks, 128)
    rows[:, 0, 0] = bias
    rows[:, 1:, :32] = torch.nn.functional.pad(weight, (0, 32 * blocks - k)).reshape(n, blocks, 32)
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - (6 if k <= 16 else 4))
    coarse = torch.round(rows / step) * step
    if k > 32 and k % 2 == 0:
        # Use one small shared correction for each adjacent pair. Anchor it
        # on the coarser grid so the larger coefficient is represented well.
        taps = rows[:, 1:, :32]
        _, element_exp = torch.frexp(taps.abs())
        grid = torch.ldexp(torch.ones_like(taps), torch.maximum(element_exp, exponent[:, 1:] - 2) - 6)
        w = taps.reshape(n, blocks, 16, 2)
        g = grid.reshape_as(w)
        remainder = w - (w / g).round() * g
        anchor = torch.where(g[..., :1] >= g[..., 1:], remainder[..., :1], remainder[..., 1:])
        correction = (w - ((w - anchor) / g).round() * g).mean(dim=-1, keepdim=True)
        main = torch.nn.functional.pad((w - correction).flatten(-2), (0, 96))
        offsets = torch.nn.functional.pad(correction.squeeze(-1), (0, 112))
        w_rows = torch.stack((main, offsets), dim=2).reshape(n, -1, 128)
        return {'coeff': torch.cat((coarse[:, :1], (rows - coarse)[:, :1], w_rows), dim=1).reshape(-1, 128)}
    return {'coeff': torch.stack((coarse, rows - coarse), dim=2).reshape(-1, 128)}
