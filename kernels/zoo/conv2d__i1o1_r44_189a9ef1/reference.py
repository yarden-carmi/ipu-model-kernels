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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 128, 128], [1048576, 16384, 128, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 32, 128, 128])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Lay out weights by output block, tap, and input channel."""
    weight = module.weight
    co, ci, kh, kw = weight.shape
    blocks = (co + 127) // 128
    panel = (ci + 15) // 16 * 16
    rows = weight.new_zeros((blocks, 1 + kh * kw * panel, 128))
    taps = rows[:, 1:].view(blocks, kh, kw, panel, 128)
    bias = getattr(module, "bias", None) if params.get("bias") else None
    for block, start in enumerate(range(0, co, 128)):
        tile = weight[start:start + 128]
        active = tile.shape[0]
        taps[block, :, :, :ci, :active] = tile.permute(2, 3, 1, 0)
        if bias is not None:
            rows[block, 0, :active] = bias.reshape(-1)[start:start + active]
    return {"weights": rows}
