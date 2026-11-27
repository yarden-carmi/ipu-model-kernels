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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 56, 56], [200704, 3136, 56, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 64, 56, 56], [200704, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 64, 56, 56])}
# ---- end of the frozen reference ----


def fold(module, **params):
    scale = module.op1_weight.to(torch.float64) / torch.sqrt(
        module.op1_running_var.to(torch.float64) + 1e-5
    )
    weight = module.op0_weight.to(torch.float64) * scale[:, None, None, None]
    cout, cin, kh, kw = weight.shape
    blocks = (cin + 127) // 128
    padded = weight.new_zeros((cout, blocks * 128, kh, kw))
    padded[:, :cin] = weight
    rows = weight.new_zeros((cout, 1 + kh * kw * blocks, 128))
    rows[:, 1:] = padded.reshape(cout, blocks, 128, kh, kw).permute(
        0, 3, 4, 1, 2
    ).reshape(cout, kh * kw * blocks, 128)
    rows[:, 0, 0] = module.op1_bias.to(torch.float64) - module.op1_running_mean.to(torch.float64) * scale
    maximum = rows.abs().amax(dim=-1, keepdim=True)
    step = torch.where(maximum > 0, torch.pow(2.0, torch.floor(torch.log2(maximum.clamp_min(1e-300))) - 1), 1.0)
    high = torch.round(rows / step) * step
    return {"weights": torch.stack((high, rows - high), dim=2).reshape(cout, -1, 128)}
