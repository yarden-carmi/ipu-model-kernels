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
    r0 = aten.linear.default(_v(ins[0], [1, 257, 1536], [394752, 1536, 1], 0), module.op0_weight, module.op0_bias)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.mul.Tensor(_v(op0, [1, 257, 384], [98688, 384, 1], 0), module.op1_lambda1)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 257, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold the channel scale into both affine terms and pack output-channel tiles."""
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
    # E1 gives the unsplit rows more mantissa precision, so only half
    # the full K chunks need a separate residual row for each weight row.
    refined = (k // 128) // 2
    head = rows[:, :1 + 128 * refined]
    exp = torch.frexp(head.abs().amax(dim=-1, keepdim=True))[1]
    hi = torch.ldexp(torch.ldexp(head, 5 - exp).round(), exp - 5)
    head = torch.stack((hi, head - hi), dim=2).flatten(1, 2)
    return {"w": torch.cat((head, rows[:, 1 + 128 * refined:]), dim=1).reshape(-1, 128).float()}
