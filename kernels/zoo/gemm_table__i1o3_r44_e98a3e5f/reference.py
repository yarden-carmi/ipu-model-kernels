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
    r0 = aten.conv2d.default(_v(ins[0], [1, 40, 14, 14], [7840, 196, 14, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 240, 14, 14], [47040, 196, 14, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.hardswish_.default(_v(op1, [1, 240, 14, 14], [47040, 196, 14, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 240, 14, 14])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch normalization and split rows into NX8 digits."""
    n, k = params['n'], params['k']
    if hasattr(module, 'op0_weight'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        if getattr(module, 'op0_bias', None) is not None:
            bias = bias + module.op0_bias.double() * scale
    else:
        weights = module.weight.double().reshape(n, k)
        bias = getattr(module, 'bias', None)
    if bias is None or not params['bias']:
        bias = weights.new_zeros(n)

    def split(rows, digits):
        parts = []
        for _ in range(digits - 1):
            _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
            step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 6)
            digit = (rows / step).round().clamp(-63, 63) * step
            parts.append(digit)
            rows = rows - digit
        return torch.stack([*parts, rows], dim=1).reshape(-1, 128)

    width = params['out0_d3']
    pack = 128 // width
    bias = torch.nn.functional.pad(bias.double(), (0, (-n) % pack))
    bias = bias.reshape(-1, pack).repeat_interleave(width, dim=1)
    return {
        'weights': split(torch.nn.functional.pad(weights, (0, 128 - k)), 3),
        'bias_rows': split(torch.nn.functional.pad(bias, (0, 128 - pack * width)), 2),
    }
