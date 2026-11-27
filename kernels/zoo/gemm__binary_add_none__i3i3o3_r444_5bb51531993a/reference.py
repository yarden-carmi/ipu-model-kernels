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
    r0 = aten.conv2d.default(_v(ins[0], [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    op1 = r_(op1, "s0")  # stored
    r0 = aten.add.Tensor(_v(op1, [1, 64, 64, 64], [262144, 4096, 64, 1], 0), _v(ins[1], [1, 64, 64, 64], [262144, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 1
    return {"out0": _out(op2, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold batch norm and pack scalar coefficients for spatial-vector MACs."""
    n, k = params["s0_n"], params["s0_k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    groups = (k + 31) // 32
    padded = torch.nn.functional.pad(weight, (0, groups * 32 - k)).reshape(n, groups, 32)
    coeff = weight.new_zeros((n, 2 + 2 * groups, 128))
    if params["s0_bias"] and bias is not None:
        bias = bias.double()
        quantum = torch.ldexp(torch.ones_like(bias), torch.frexp(bias.abs())[1] - 5)
        hi = torch.round(bias / quantum) * quantum
        coeff[:, 0, :] = hi[:, None]
        coeff[:, 1, :] = (bias - hi)[:, None]
    quantum = torch.ldexp(torch.ones_like(padded[:, :, :1]), torch.frexp(padded.abs().amax(-1, keepdim=True))[1] - 5)
    hi = torch.round(padded / quantum) * quantum
    omitted = [i for i in range(32) if i % 3 == 2 or i in (13, 27, 31)]
    hi[..., omitted] = padded[..., omitted]
    coeff[:, 2::2, :32] = hi
    coeff[:, 3::2, :19] = (padded - hi)[..., [i for i in range(32) if i not in omitted]]
    return {"w": coeff.reshape(-1, 128)}
