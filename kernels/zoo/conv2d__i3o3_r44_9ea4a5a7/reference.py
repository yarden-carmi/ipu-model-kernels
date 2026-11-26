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
    """Fuse inference batch norm and lay out bias and tap panels per channel."""
    weight = getattr(module, "op0_weight", getattr(module, "weight", None)).detach().double()
    co, ci, kh, kw = weight.shape
    bias = getattr(module, "op0_bias", getattr(module, "bias_vec", getattr(module, "bias", None)))
    bias = weight.new_zeros(co) if bias is None else bias.detach().double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None, None, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale

    stride = params["stride"]
    taps = weight.permute(0, 2, 1, 3).reshape(co, -1).repeat_interleave(stride, dim=1) * 2.0**-16
    panels = torch.nn.functional.pad(taps, (0, (-taps.shape[1]) % 128)).reshape(co, -1, 128)
    seed = bias[:, None, None].expand(-1, 1, 128)

    ow, iw, pad = (params[k] for k in ("out0_d3", "in0_d3", "padding"))
    masks = weight.new_zeros((1 + 2 * kw, 128))
    x = torch.arange(ow, device=weight.device) * stride
    for half in range(2):
        for kx in range(kw):
            ix = x + kx - pad
            masks[1 + half * kw + kx, x + half * ow * stride] = ((ix >= 0) & (ix < iw)).to(weight.dtype) * 2.0**16
    def split(rows):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exponent.double() - 6)
        high = (rows / step).round().clamp(-63, 63) * step
        return high, rows - high

    return {"weights": torch.cat((*split(seed), *split(panels)), dim=1).reshape(-1, 128), "masks": masks}
