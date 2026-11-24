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
    r0 = aten.linear.default(_v(ins[0], [1, 1829, 384], [702336, 384, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 1829, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold the channel scale into both affine terms, then pack high and residual planes."""
    k, n = int(params["k"]), int(params["n"])
    if hasattr(module, "op1_lambda1"):
        scale = module.op1_lambda1.detach().reshape(n).double()
        w = module.op0_weight.detach().reshape(n, k).double() * scale[:, None]
        b = module.op0_bias.detach().reshape(n).double() * scale if params["bias"] else w.new_zeros(n)
    else:
        source = getattr(module, "op0_weight", getattr(module, "weight", None))
        w = source.detach().double()
        if w.shape != (n, k):
            w = w.reshape(k, n).T
        bias = getattr(module, "op0_bias", getattr(module, "bias", None))
        b = bias.detach().double().reshape(n) if params["bias"] and bias is not None else w.new_zeros(n)
    data = torch.cat((b[:, None], w), dim=1)
    data = torch.nn.functional.pad(data, (0, 0, 0, (-n) % 128))
    rows = data.reshape(-1, 128, k + 1).transpose(1, 2)
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    hi = torch.ldexp(torch.ldexp(rows, 5 - exp).round(), exp - 5)
    planes = (hi, rows - hi)
    return {"w": torch.stack(planes, dim=2).reshape(-1, 128).float()}
