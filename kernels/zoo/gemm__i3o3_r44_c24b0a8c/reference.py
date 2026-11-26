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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 16, 56, 56])}
# ---- end of the frozen reference ----


def _digits(rows):
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exponent - 4)
    high = torch.round(rows / step) * step
    return torch.stack((high, rows - high), dim=-2)


def fold(module, **params):
    """Fold inference BN and split tap rows into coarse and residual digits."""
    n, k = params['n'], params['k']
    weight = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    weight = weight.detach().double().reshape(n, k)
    offset = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    offset = weight.new_zeros(n) if offset is None else offset.detach().double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        offset = module.op1_bias.double() + (offset - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None]

    pad = torch.nn.functional.pad
    taps = pad(weight, (0, (-k) % 32)).reshape(n, -1, 32)
    rows = pad(_digits(taps), (0, 96)).reshape(n, -1, 128)
    if params['bias']:
        rows = torch.cat((_digits(offset[:, None].expand(-1, 128)), rows), dim=1)
    return {'w' if params['bias'] else 'w_unbiased': rows.reshape(-1, 128)}
