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
    weight,bias = module.weight,module.bias
    i,o,a,b = weight.shape
    q = weight.float().reshape(i//48,3,16,o*a*b//16,16)
    drop = q.square().sum((2,4)).argmin(1,keepdim=True)
    keep = (torch.arange(3,device=q.device).reshape(1,3,1)!=drop)
    w = (q*keep[:,:,None,:,None]).reshape(i,-1)
    t = (x.movedim(-3,-1).float() @ w).movedim(-1,-3)
    return torch.nn.functional.pixel_shuffle(t+bias.float().repeat_interleave(a*b).reshape(-1,1,1),a).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 96, 16, 16], [24576, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    i, o, a, b = module.weight.shape
    panels = module.weight.float().reshape(i // 48, 3, 16, o * a * b // 16, 16)
    drop = panels.square().sum((2, 4)).argmin(1, keepdim=True)
    ids = torch.arange(3, device=panels.device).reshape(1, 3, 1)
    kept = torch.where((ids != drop)[:, :, None, :, None], panels, 0).reshape(i, -1)
    bias = module.bias.float().repeat_interleave(a * b).unsqueeze(0)
    rows = torch.cat((bias, kept), dim=0)
    chunks = (rows.shape[1] + 127) // 128
    rows = torch.nn.functional.pad(rows, (0, chunks * 128 - rows.shape[1]))
    return {"weights": rows.reshape(i + 1, chunks, 128).transpose(0, 1).contiguous().reshape(-1, 128)}
