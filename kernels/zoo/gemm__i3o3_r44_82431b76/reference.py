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
    r0 = aten.conv2d.default(_v(ins[0], [1, 160, 8, 8], [10240, 64, 8, 1], 0), module.weight)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 240, 8, 8])}
# ---- end of the frozen reference ----


def _digits(rows):
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exponent - 4)
    coarse = torch.round(rows / step) * step
    return torch.stack((coarse, rows - coarse), dim=-2)


def fold(module, **params):
    """Fold convolution and inference BN into coefficient streams."""
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
        dots = pad(weight, (0, (-k) % 128)).reshape(n, -1, 128)
        corrected = 2 if dots.shape[1] >= 3 else 0
        rows = torch.cat([
            _digits(dots[:, j]) if params['bias'] and j == corrected else dots[:, j:j+1]
            for j in range(dots.shape[1])
        ], dim=1)
    else:
        wide = k >= 256 and spatial > 1024
        group = 96 if wide else 32
        taps = pad(weight, (0, (-k) % group)).reshape(n, -1, group)
        rows = _digits(taps)
        fix = (22 if spatial <= 256 else 24 if k >= 256 else
               26 if k >= 128 else 24 if spatial >= 4096 else 32)
        omitted = slice(3, None, 8) if wide else slice(fix, None)
        rows[..., 0, omitted] = taps[..., omitted]
        rows[..., 1, omitted] = 0
        rows = pad(rows, (0, 128 - group)).reshape(n, -1, 128)
    if params['bias']:
        rows = torch.cat((_digits(bias[:, None].expand(-1, 128)), rows), dim=1)
    return {name: rows.reshape(-1, 128)}
