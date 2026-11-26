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
    r0 = aten.conv2d.default(_v(ins[0], [1, 88, 28, 28], [68992, 784, 28, 1], 0), module.op0_weight, None, [1, 1], [1, 1], [1, 1], 88)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 88, 28, 28], [68992, 784, 28, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 88, 28, 28], [68992, 784, 28, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 88, 28, 28])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference BN, then put padding masks in the tap vectors."""
    if hasattr(module, 'op0_weight'):
        weight = module.op0_weight.double()
        scale = module.op1_weight.double() * (module.op1_running_var.double() + 1e-5).rsqrt()
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        weight = weight * scale[:, None, None, None]
    else:
        weight = module.weight.double()
        bias = module.bias.double() if params['bias'] else weight.new_zeros(weight.shape[0])

    cout, group_in, kh, kw = weight.shape
    ih, iw = params['in0_d2'], params['in0_d3']
    oh, ow = params['out0_d2'], params['out0_d3']
    blocks = (oh * ow + 127) // 128
    p = torch.arange(blocks * 128, device=weight.device).view(blocks, 128)
    y, x = p // ow, p % ow
    dy = torch.arange(kh, device=p.device)[:, None, None, None] - params['padding']
    dx = torch.arange(kw, device=p.device)[None, :, None, None] - params['padding']
    sy, sx = y + dy, x + dx
    valid = (p < oh * ow) & (sy >= 0) & (sy < ih) & (sx >= 0) & (sx < iw)
    taps = weight[..., None, None] * valid
    taps = taps.permute(0, 4, 1, 2, 3, 5).reshape(cout, blocks, -1, 128)
    rows = torch.cat(((bias[:, None, None] * (p < oh * ow)).unsqueeze(2), taps), dim=2)

    def digit(values):
        _, exp = torch.frexp(values.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exp.double() - 6)
        return (values / step).round().clamp(-63, 63) * step

    hi = digit(rows)
    remainder = rows - hi
    mid = digit(remainder)
    return {'weights': torch.stack((hi, mid, remainder - mid), dim=-2).reshape(-1, 128)}
