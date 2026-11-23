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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.weight
    co, ci, _, _ = weight.shape
    bias = getattr(module, "bias", None) if params["bias"] else None
    if params["in0_d3"] == 8:
        rows = weight.new_zeros((1 + co * (1 + 9 * ci), 128))
        panels = rows[1:].view(co, 1 + 9 * ci, 128)
        if bias is not None:
            panels[:, 0] = bias.reshape(co, 1)
        taps = panels[:, 1:].view(co, ci, 3, 3, 128)
        taps[:] = weight.unsqueeze(-1)
        taps[:, :, :, 0, ::8] = 0
        taps[:, :, :, 2, 7::8] = 0
        if params["in0_d2"] <= 16:
            taps[:, :, 2, :, (params["in0_d2"] - 1) * 8:] = 0
    else:
        blocks = (ci + 13) // 14
        rows = weight.new_zeros((1 + co * blocks, 128))
        panels = rows[1:].view(co, blocks, 128)
        taps = weight.new_zeros((co, blocks * 14, 3, 3))
        taps[:, :ci] = weight
        panels[:, :, :126] = taps.reshape(co, blocks, 126)
        if bias is not None:
            panels[:, 0, 126] = bias.reshape(co)
    rows = rows.double()
    pieces = []
    for _ in range(2 if params["in0_d3"] == 8 else 1):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exponent.double() - 6)
        hi = (rows / step).round().clamp(-63, 63) * step
        pieces.append(hi)
        rows = rows - hi
    pieces.append(rows)
    packed = torch.stack(pieces, dim=1)[1:].reshape(-1, 128)
    return {"weights": torch.cat((rows[:1], packed))}
