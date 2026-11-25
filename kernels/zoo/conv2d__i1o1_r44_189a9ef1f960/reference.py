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
    """Fuse inference batch normalization and lay out [tap, input, output]."""
    weight = module.op0_weight.detach().double()
    cin, cout, groups = (params[k] for k in ("cin", "cout", "groups"))
    bias = getattr(module, "op0_bias", None)
    bias = weight.new_zeros(cout) if bias is None else bias.detach().double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None, None, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale

    taps = weight.new_zeros((params["kh"] * params["kw"], cin, 128))
    ni, no = cin // groups, cout // groups
    for g in range(groups):
        out = slice(g * no, (g + 1) * no)
        taps[:, g * ni:(g + 1) * ni, out] = weight[out].flatten(2).permute(2, 1, 0)
    bias = torch.nn.functional.pad(bias, (0, 128 - cout))[None]

    def split(rows):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exponent.double() - 6)
        high = (rows / step).round().clamp(-63, 63) * step
        return high, rows - high

    return {"weights": torch.cat((*split(bias), torch.cat(split(taps), dim=1).flatten(0, 1)))}
