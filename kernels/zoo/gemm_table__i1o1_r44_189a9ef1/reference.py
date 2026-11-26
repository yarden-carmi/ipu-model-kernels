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


def fold(module, **params):
    """Fold inference batch norm and pack coefficient rows in tap order."""
    k, n = params['k'], params['n']
    weight = getattr(module, 'op0_weight', getattr(module, 'weight', None)).double().reshape(n, k)
    raw_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weight.new_zeros(n) if raw_bias is None else raw_bias.double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None]
        bias = (bias - module.op1_running_mean.double()) * scale + module.op1_bias.double()
    if not params['bias']:
        bias = torch.zeros_like(bias)
    rows = torch.nn.functional.pad(torch.cat((bias[None], weight.T)), (0, (-n) % 128))
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    pairs = _digits(rows, 4)
    packed = [pairs[:, 0]]
    if k in (64, 96):
        # Offset both taps before quantizing; multiply the offset by their sum.
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        _, element_exp = torch.frexp(rows.abs())
        grid = torch.ldexp(torch.ones_like(rows), torch.maximum(element_exp, exponent - 2) - 6)
        for j in range(1, k + 1, 2):
            w, g = rows[:, j:j+2], grid[:, j:j+2]
            residual = w - (w / g).round() * g
            anchor = torch.where(g[:, :1] >= g[:, 1:], residual[:, :1], residual[:, 1:])
            coarse = ((w - anchor) / g).round() * g
            offset = (w - coarse).mean(dim=1, keepdim=True)
            packed.extend((offset, w - offset))
        return {'coeff': torch.cat(packed, dim=1).reshape(-1, 128)}
    splits = 9 if k <= 16 else 24 if k <= 64 else 22 if k <= 128 else 16
    for tap in range(k):
        packed.append(pairs[:, tap + 1] if tap % 32 < splits else rows[:, tap + 1:tap + 2])
    return {'coeff': torch.cat(packed, dim=1).reshape(-1, 128)}
