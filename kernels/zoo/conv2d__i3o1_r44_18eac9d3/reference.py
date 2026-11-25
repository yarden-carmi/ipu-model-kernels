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
    r0 = aten.conv2d.default(_v(ins[0], [1, 48, 64, 64], [196608, 4096, 64, 1], 0), module.weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.weight
    co, ci, kh, kw = weight.shape
    ow = params["out0_d3"]
    pack = 2 if co <= 64 and ow % 2 == 0 else 1
    blocks = (co + 127) // 128
    taps = kh * ci * kw
    rows = weight.new_zeros((blocks, 1 + pack * taps, 128))
    bias = getattr(module, "bias_vec", None)
    if bias is None:
        bias = getattr(module, "bias", None)
    for block in range(blocks):
        start = block * 128
        stop = min(start + 128, co)
        width = stop - start
        panel = weight[start:stop].permute(2, 1, 3, 0).reshape(taps, width)
        for slot in range(pack):
            lanes = slice(slot * width, (slot + 1) * width)
            rows[block, 1 + slot * taps:1 + (slot + 1) * taps, lanes] = panel
            if params.get("bias") and bias is not None:
                rows[block, 0, lanes] = bias.reshape(-1)[start:stop]
    return {"weights": rows}
