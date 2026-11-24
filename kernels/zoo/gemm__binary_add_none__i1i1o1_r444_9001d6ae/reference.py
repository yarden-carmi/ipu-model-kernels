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
    r0 = aten.conv2d.default(_v(ins[0], [1, 88, 28, 28], [68992, 784, 28, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 24, 28, 28], [18816, 784, 28, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    op1 = r_(op1, "s0")  # stored
    r0 = aten.add.Tensor(_v(op1, [1, 24, 28, 28], [18816, 784, 28, 1], 0), _v(ins[1], [1, 24, 28, 28], [18816, 784, 28, 1], 0))
    op2 = _pick(r0, 0)  # step 1
    return {"out0": _out(op2, [1, 24, 28, 28])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold batch norm and stream two precision digits per coefficient row."""
    n, k = params["s0_n"], params["s0_k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    chunks = (k + 127) // 128
    padded = torch.nn.functional.pad(weight, (0, chunks * 128 - k))
    coeff = weight.new_zeros((1 + chunks * n, 128))
    if params["s0_bias"] and bias is not None:
        coeff[0, :2*n] = bias.repeat(2)
    coeff[1:] = padded.reshape(n, chunks, 128).transpose(0, 1).reshape(-1, 128)
    exponent = torch.frexp(coeff.abs().amax(dim=1, keepdim=True))[1]
    quantum = torch.ldexp(torch.ones_like(coeff[:, :1]), exponent - 5)
    hi = torch.round(coeff / quantum) * quantum
    return {"w": torch.stack((hi, coeff - hi), dim=1).reshape(-1, 128)}
