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
    r0 = aten.linear.default(_v(ins[0], [1, 257, 384], [98688, 384, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 257, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Split blocked coefficients into independently scaled signed radix-64 digits."""
    weight = getattr(module, "op0_weight", getattr(module, "weight", None)).detach().double()
    n, k = weight.shape
    source_bias = getattr(module, "op0_bias", getattr(module, "bias", None))
    bias = source_bias.detach().double() if params["bias"] else weight.new_zeros(n)
    if hasattr(module, "op1_lambda1"):
        scale = module.op1_lambda1.detach().reshape(n).double()
        weight = (weight * scale[:, None]).float().double()
        bias = (bias * scale).float().double()
    coefficients = torch.cat((bias[:, None], weight), dim=1)
    coefficients = torch.nn.functional.pad(coefficients, (0, 0, 0, (-n) % 128))
    rows = coefficients.reshape(-1, 128, k + 1).transpose(1, 2)
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(rows.abs(), 24 - exp).round().long().clamp(max=(1 << 24) - 1)
    planes = [torch.ldexp(((digits >> shift) & 63) * rows.sign(), exp + shift - 24)
              for shift in (18, 12, 6, 0)]
    return {"w": torch.stack(planes, dim=2).reshape(-1, 128).float()}
