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
    r0 = aten.conv2d.default(_v(ins[0], [1, 40, 1, 1], [40, 1, 1, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.hardsigmoid.default(_v(op0, [1, 144, 1, 1], [144, 1, 1, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 144, 1, 1])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Tile channels and retain residuals for most spatial GEMM rows."""
    n, k = params['n'], params['k']
    blocks = (n + 127) // 128
    if hasattr(module, 'op0_weight'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weights = module.weight.double().reshape(n, k)
        bias = getattr(module, 'bias', None)
    if bias is None or not params['bias']:
        bias = weights.new_zeros(n)

    rows = weights.new_zeros(blocks * 128, k + 1)
    rows[:n, 0] = bias
    rows[:n, 1:] = weights
    rows = rows.reshape(blocks, 128, k + 1).transpose(1, 2)
    if params['m'] == 1:
        return {'coeff': rows.reshape(-1, 128)}
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exp - 4)
    coarse = torch.round(rows / step) * step
    split = torch.arange(k + 1, device=rows.device) % 4 != 0
    split[0] = True
    first = torch.where(split[None, :, None], coarse, rows)
    interleaved = torch.stack((first, rows - coarse), dim=2).flatten(1, 2)
    keep = torch.stack((torch.ones_like(split), split), dim=1).flatten()
    return {'coeff': interleaved[:, keep].reshape(-1, 128)}
