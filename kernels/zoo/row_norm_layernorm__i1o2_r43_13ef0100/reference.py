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
    r0 = aten.layer_norm.default(_v(ins[0], [4, 256, 144], [1, 4, 1024], 0), [144], module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [4, 256, 144])}
# ---- end of the frozen reference ----


def fold(module, **params):
    ch = params["channels"]
    k = (ch + 127) // 128

    def split(value):
        flat = torch.zeros(((value.numel() + 127) // 128) * 128)
        flat[:value.numel()] = value.reshape(-1)
        residual = flat.reshape(-1, 128)
        parts = []
        for _ in range(2):
            peak = residual.abs().amax(dim=1, keepdim=True).clamp_min(1e-30)
            step = 2.0 ** (torch.floor(torch.log2(peak)) - 4)
            part = torch.round(residual / step) * step
            parts.append(part)
            residual = residual - part
        return torch.cat([*parts, residual])

    # Each chunk has up to two intersections with packed physical rows.
    # Row zero contains epsilon; the rest are masks in traversal order.
    n = params["out0_d1"]
    data = torch.zeros(1 + 2 * n * k, 128)
    data[0].fill_(params["eps"])
    mask = 1
    dst = 0
    for _ in range(n):
        for first in range(0, ch, 128):
            left = min(128, ch - first)
            while left:
                take = min(left, 128 - dst)
                data[mask, dst:dst + take] = 1
                mask += 1
                dst = (dst + take) % 128
                left -= take

    return {
        "gamma": split(module.weight),
        "beta": split(module.bias),
        "crow": split(torch.full((128,), 1 / ch)),
        "pack_data": data,
    }
