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
    r0 = aten.conv2d.default(_v(ins[0], [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """One output-channel vector per tap and input channel."""
    weight = module.weight
    co, ci, kh, kw = weight.shape
    blocks = (co + 127) // 128
    panel = (ci + 15) // 16 * 16
    if (ci <= 128 and co <= 32 and kh == kw == 3 and
            params["stride"] == params["padding"] == 1 and params["w"] <= 128):
        dots = weight.new_zeros((co, 10, 128))
        dots[:, 1:, :ci] = weight.permute(0, 2, 3, 1).reshape(co, 9, ci)
        if params.get("bias"):
            bias = getattr(module, "bias_vec", None)
            if bias is None:
                bias = module.bias
            dots[:, 0] = bias.reshape(co, 1)
        return {"weights": dots.reshape(-1, 128)}
    rows = weight.new_zeros((blocks, 1 + kh * kw * panel, 128))
    taps = rows[:, 1:].view(blocks, kh, kw, panel, 128)
    for block in range(blocks):
        vector = weight[block * 128:(block + 1) * 128]
        taps[block, :, :, :ci, :len(vector)] = vector.permute(2, 3, 1, 0)
    if params.get("bias"):
        bias = getattr(module, "bias_vec", None)
        if bias is None:
            bias = module.bias
        for block in range(blocks):
            values = bias.reshape(-1)[block * 128:(block + 1) * 128]
            rows[block, 0, :values.numel()] = values
    return {"weights": rows.reshape(-1, 128)}
