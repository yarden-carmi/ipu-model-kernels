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
    r0 = aten.conv2d.default(_v(ins[0], [1, 192, 16, 16], [49152, 256, 16, 1], 0), module.weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.weight
    co, ci, kh, kw = weight.shape
    chunks = (ci + 127) // 128
    blocks = (co + 127) // 128
    dot = (co < ci or co <= 32) and co <= 128
    panel = chunks * co if dot else (ci + 15) // 16 * 16
    rows = weight.new_zeros((blocks, 1 + kh * kw * panel, 128))
    if dot:
        padded = weight.new_zeros((co, chunks * 128, kh, kw))
        padded[:, :ci] = weight
        rows[0, 1:] = padded.view(co, chunks, 128, kh, kw).permute(3, 4, 1, 0, 2).reshape(-1, 128)
    else:
        padded = weight.new_zeros((blocks * 128, ci, kh, kw))
        padded[:co] = weight
        rows[:, 1:].view(blocks, kh, kw, panel, 128)[:, :, :, :ci] = (
            padded.view(blocks, 128, ci, kh, kw).permute(0, 3, 4, 2, 1)
        )
    if params.get("bias"):
        bias = getattr(module, "bias_vec", None)
        if bias is None:
            bias = module.bias
        padded_bias = weight.new_zeros(blocks * 128)
        padded_bias[:co] = bias.reshape(-1)
        rows[:, 0] = padded_bias.view(blocks, 128)
    return {"weights": rows}
