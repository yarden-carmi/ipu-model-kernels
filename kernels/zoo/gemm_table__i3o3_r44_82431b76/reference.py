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


def fold(module, **params):
    """Fold batch normalization and tile coefficients by output channel."""
    n, k = params["n"], params["k"]
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    if getattr(module, "op0_bias", None) is not None:
        bias = bias + module.op0_bias.double() * scale
    def split(x, peak):
        _, exponent = torch.frexp(peak)
        step = torch.ldexp(torch.ones_like(peak), exponent - 4)
        coarse = torch.round(x / step) * step
        return coarse, x - coarse

    rows = weight.new_zeros(n, 2 + 2 * ((k + 31) // 32), 128)
    if params["bias"]:
        rows[:, 0, 0], rows[:, 1, 0] = split(bias, bias.abs())
    for block, taps in enumerate(weight.split(32, dim=1), start=1):
        width = taps.shape[1]
        if (k == 32) or (96 <= k < 128 and k % 32 == 0):
            # One offset per tap group, selected to reduce coefficient-grid error.
            _, exp = torch.frexp(taps.abs().amax(dim=1, keepdim=True))
            guard = torch.ldexp(torch.ones_like(taps[:, :1]), exp - 1)
            shifts = guard[:, :, None] * torch.linspace(-1/32, 1/32, 129, device=taps.device, dtype=taps.dtype)
            start = 0
            for group, length in enumerate((2,) * 16 if k == 32 else (5, 5, 5, 5, 4, 4, 4)):
                w = taps[:, start:start + length]
                shifted = w.unsqueeze(-1) - shifts
                _, ex = torch.frexp(shifted.abs())
                step = torch.ldexp(torch.ones_like(shifted), torch.maximum(ex, exp[:, :, None] - 2) - 6)
                error = shifted - (shifted / step).round() * step
                ix = (error.square().sum(dim=1) + error.sum(dim=1).square() / 2).argmin(dim=-1, keepdim=True)
                offset = shifts[:, 0].gather(-1, ix)
                rows[:, 2 * block, start:start + length] = w - offset
                rows[:, 2 * block + 1, group] = offset[:, 0]
                start += length
            rows[:, 2 * block, 32] = guard[:, 0]
            continue
        rows[:, 2 * block, :width], rows[:, 2 * block + 1, :width] = split(
            taps, taps.abs().amax(dim=1, keepdim=True))
    return {"coeff": rows.flatten(0, 1)}
