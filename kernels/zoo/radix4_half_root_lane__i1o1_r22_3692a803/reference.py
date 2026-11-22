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


# the replacement's recorded code (§4.6), the operation of op0
def forward(module, *inputs):
    import torch
    x = inputs[0]
    t = {torch.float32: 23, torch.float16: 10, torch.bfloat16: 7}.get(x.dtype)
    if t is None:
        return torch.sqrt(x)
    v = x.float()
    live = (v > 0) & torch.isfinite(v)
    m, e = torch.frexp(torch.where(live, v, 1.0))
    j = e - 1
    p = j & 1
    q = (j - p) // 2
    a = (m * (1 << (t + 1))).to(torch.int64) << (t + p).to(torch.int64)
    r = torch.zeros_like(a)
    rem = torch.zeros_like(a)
    for i in range(t, -1, -1):
        rem = (rem << 2) | ((a >> (2 * i)) & 3)
        trial = (r << 2) | 1
        take = rem >= trial
        rem = torch.where(take, rem - trial, rem)
        r = (r << 1) | take.to(torch.int64)
    r = r + (rem > r).to(torch.int64)
    y = torch.ldexp(r.float(), q - t).to(x.dtype)
    return torch.where(live, y, torch.where(x < 0, float('nan'), x))


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 1], [1, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 1])}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
