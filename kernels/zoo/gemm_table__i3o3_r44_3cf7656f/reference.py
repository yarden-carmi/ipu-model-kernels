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
    """Fold batch normalization into GEMM, then split each coefficient row."""
    n, k = params['n'], params['k']
    width = params['out0_d3']
    pack = min(n, 128 // width)
    if n % pack:
        pack = 1
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    if not params['bias']:
        bias = torch.zeros_like(bias)

    in_pack = 128 // width
    if 128 % width or k % in_pack:
        in_pack = 1
    channels = torch.arange(pack)
    if in_pack > 1:
        rotation = torch.arange(in_pack)[:, None]
        index = (rotation + channels) % in_pack
        weights = weight.reshape(n // pack, pack, k // in_pack, in_pack)
        weights = weights.permute(0, 2, 1, 3)
        index = index.T[None, None].expand_as(weights)
        weights = weights.gather(-1, index).transpose(-1, -2).reshape(n // pack, k, pack)
    else:
        weights = weight.reshape(n // pack, pack, k).transpose(1, 2)
        weights = (weights[:, :, None, :] * torch.eye(pack, dtype=weight.dtype)).flatten(1, 2)
    values = torch.cat((bias.reshape(n // pack, 1, pack), weights), dim=1)
    rows = values.repeat_interleave(width, dim=-1)
    rows = torch.nn.functional.pad(rows, (0, 128 - pack * width))
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exp, dtype=rows.dtype), exp - 4)
    coarse = torch.round(rows / step) * step
    digits = torch.stack((coarse, rows - coarse), dim=-2).reshape(-1, 128)
    return {'coeff': torch.nn.functional.pad(digits, (0, 0, 1, 0))}
