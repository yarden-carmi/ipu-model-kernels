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
    r0 = aten.conv2d.default(_v(ins[0], [1, 128, 16, 16], [32768, 256, 16, 1], 0), module.weight)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 192, 16, 16])}
# ---- end of the frozen reference ----


def _split(rows):
    """A four-bit leading digit and its residual, with independent row scales."""
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exp - 4)
    hi = torch.round(rows / step) * step
    return hi, rows - hi


def fold(module, **params):
    n, k = params["n"], params["k"]
    source = getattr(module, "weight", getattr(module, "op0_weight", None))
    if source is None:
        raise ValueError(f"Unrecognized GEMM parameters: {[(name, tuple(t.shape)) for name, t in vars(module).items()]}")
    weights = source.detach().double().reshape(n, k)
    bias = getattr(module, "bias", getattr(module, "op0_bias", None))
    bias = bias.detach().double().reshape(n) if params["bias"] and bias is not None else weights.new_zeros(n)
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = weights * scale[:, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
    depth = ((k + 127) // 128) * 128
    if n != params["out0_d2"] or k != params["in0_d2"] or params["m"] != params["in0_d0"] * params["in0_d1"]:
        # Spatial output: each weight row supplies 128 reduction terms.
        rows = torch.nn.functional.pad(weights, (0, depth - k)).reshape(n, -1, 128)
        b = bias[:, None].expand(n, 128)
        return {"w": torch.cat((torch.stack(_split(b), dim=1),
                                torch.stack(_split(rows), dim=2).flatten(1, 2)), dim=1).reshape(-1, 128)}

    # Output-channel-vector path: each weight row supplies one output tile.
    width = ((n + 127) // 128) * 128
    rows = torch.nn.functional.pad(weights, (0, 0, 0, width - n))
    rows = rows.reshape(-1, 128, k).transpose(1, 2)
    b = torch.nn.functional.pad(bias, (0, width - n)).reshape(-1, 128)
    return {"w": torch.cat((torch.stack(_split(b), dim=1),
                            torch.stack(_split(rows), dim=2).flatten(1, 2)), dim=1).reshape(-1, 128)}
