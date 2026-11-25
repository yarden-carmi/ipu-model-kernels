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
    r0 = aten.conv2d.default(_v(ins[0], [1, 128, 64, 64], [524288, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch norm and split weights into coarse and residual rows."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)

    def digits(rows):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(rows[..., :1]), exponent - 4)
        coarse = torch.round(rows / step) * step
        return torch.stack((coarse, rows - coarse), dim=-2)

    if not params["bias"] or bias is None:
        bias = weight.new_zeros(n)
    pad = torch.nn.functional.pad
    tiny = (params['in0_d2'] * params['in0_d3'] == 64 and k % 2 == 0
            and params['in0_d0'] == 1 and k <= 1024)
    if tiny:
        chunks = (k + 127) // 128
        dots = pad(weight, (0, chunks * 128 - k)).reshape(n, chunks, 128)
        rows = digits(dots).reshape(n, -1, 128)
        if not params['bias']:
            # Use a full-precision FP8 row for complete dot blocks; retain the
            # split representation in the last block.
            rows[:, 0:-2:2] = dots[:, :-1]
            rows[:, 1:-2:2] = 0
    else:
        blocks = (k + 31) // 32
        taps = pad(weight, (0, blocks * 32 - k)).reshape(n, blocks, 32)
        rows = pad(digits(taps), (0, 96)).reshape(n, -1, 128)
    rows = torch.cat((digits(bias.reshape(n, 1).expand(-1, 128)), rows), dim=1)
    return {"coeff": rows.reshape(-1, 128)}
