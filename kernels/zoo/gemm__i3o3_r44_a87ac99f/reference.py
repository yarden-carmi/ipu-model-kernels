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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 128, 128], [1048576, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 32, 128, 128], [524288, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 32, 128, 128])}
# ---- end of the frozen reference ----


def _digits(rows):
    """Split into a leading digit and a separately quantized residual."""
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exp - 4)
    hi = torch.round(rows / step) * step
    return torch.stack((hi, rows - hi), dim=-2)


def fold(module, **params):
    n, k = params["n"], params["k"]
    source = getattr(module, "weight", getattr(module, "op0_weight", None))
    weights = source.detach().double().reshape(n, k)
    source_bias = getattr(module, "bias", getattr(module, "op0_bias", None))
    bias = source_bias.detach().double().reshape(n) if params["bias"] and source_bias is not None else weights.new_zeros(n)
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = weights * scale[:, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale

    spatial = params['in0_d2'] * params['in0_d3']
    small = spatial == 64 and k % 2 == n % 2 == 0 and 128 % params['in0_d3'] == 0 and params['in0_d0'] == 1
    if not small:
        blocks = (k + 31) // 32
        padded = torch.nn.functional.pad(weights, (0, blocks * 32 - k)).reshape(n, blocks, 32)
        pack3 = params['in0_d3'] == 32 and params['in0_d2'] % 4 == 0 and k <= 96
        count = 16 if pack3 and not params['bias'] else (22 if spatial <= 256 else ((25 if spatial > 1024 else 24) if k >= 256 else (26 if k >= 128 else 32)))
        high, low = _digits(padded).unbind(-2)
        omitted = slice(12, 18) if k >= 256 and spatial > 1024 else slice(count, None)
        high[..., omitted] = padded[..., omitted]
        low[..., omitted] = 0
        rows = torch.nn.functional.pad(torch.stack((high, low), -2), (0, 96)).reshape(n, -1, 128)
        b = _digits(bias[:, None].expand(-1, 128))
        return {'w' if params['bias'] else 'w_unbiased': torch.cat((b, rows), 1).reshape(-1, 128)}

    padded_k = ((k + 127) // 128) * 128
    dots = torch.nn.functional.pad(weights, (0, padded_k - k)).reshape(n, -1, 128)
    if k >= 384:
        dots = dots.roll(-2, dims=1)
    hi, lo = _digits(dots[:, :1]).unbind(-2)
    b = _digits(bias[:, None].expand(-1, 128))
    return {"w" if params["bias"] else "w_unbiased": torch.cat((b, hi, lo, dots[:, 1:]), dim=1).reshape(-1,128)}
