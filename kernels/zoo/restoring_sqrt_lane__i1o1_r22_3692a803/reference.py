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
    p = {torch.float16:11, torch.bfloat16:8, torch.float32:24, torch.float64:53}[x.dtype]
    w = x.to(torch.float64 if p == 53 else torch.float32)
    valid = (w > 0) & torch.isfinite(w)
    m,e = torch.frexp(torch.where(valid,w,1.0))
    E = e.to(torch.int64)-1
    a = E & 1
    S = (m * (1 << p)).to(torch.int64)
    r = torch.zeros_like(S)
    rem = torch.zeros_like(S)
    for i in range(p-1,-1,-1):
        j = 2*i-(p-1)-a
        pair = torch.where(j >= 0,S >> j.clamp(min=0),S << (-j).clamp(min=0,max=2)) & 3
        rem = (rem << 2) | pair
        trial = (r << 2) | 1
        take = rem >= trial
        rem = torch.where(take,rem-trial,rem)
        r = (r << 1) | take.to(torch.int64)
    r = r + (rem > r).to(torch.int64)
    y = torch.ldexp(r.to(w.dtype) / (1 << (p-1)), ((E-a)//2).to(torch.int32))
    return torch.where(valid,y,torch.where(w < 0,float('nan'),w)).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 1], [1, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 1])}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
