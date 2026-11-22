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
    a = inputs[0]
    weight = module.weight
    bias = getattr(module, 'bias', None)
    i,o,k,l = weight.shape
    u,s,v = torch.linalg.svd(weight.permute(2,3,1,0).reshape(k*l,o,i).double(), full_matrices=False)
    r = min(i,o)*5//12
    h,w = a.shape[-2:]
    z = a.float().reshape(-1,1,i,h*w)
    y = (u[:,:,:r]*s[:,None,:r]).float() @ (v[:,:r,:].float() @ z)
    if bias is not None: y = y + bias.float().reshape(1,1,o,1)
    return y.reshape(-1,k,l,o,h,w).permute(0,3,4,1,5,2).reshape(*a.shape[:-3],o,h*k,w*l).to(a.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 48, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    i, o, k, l = module.weight.shape
    weight = module.weight.permute(2, 3, 1, 0).reshape(k * l, o, i)
    u, s, vh = torch.linalg.svd(weight.double(), full_matrices=False)
    r = min(i, o) * 5 // 12
    pad = torch.nn.functional.pad
    right = pad(vh[:, :r, :].transpose(1, 2).float(), (0, 128 - r))
    left = pad((u[:, :, :r] * s[:, None, :r]).transpose(1, 2).float(), (0, 128 - o))
    bias = getattr(module, 'bias', None)
    bias = weight.new_zeros(o) if bias is None else bias
    rows = torch.cat((pad(bias.reshape(1, o).float(), (0, 128 - o)),
                      torch.cat((right, left), dim=1).flatten(0, 1)))
    # Split into a grid-aligned leading part and an independently scaled residual.
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[:, :1]), exponent - 6)
    hi = (rows / step).trunc() * step
    return {'coeff': torch.stack((hi, rows - hi), dim=1).flatten(0, 1)}
