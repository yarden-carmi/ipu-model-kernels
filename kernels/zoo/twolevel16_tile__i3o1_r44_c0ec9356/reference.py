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
    a=inputs[0]
    w=module.weight
    b,c,h,j=a.shape
    f=w.flatten(1).reshape(c//16,16,-1)
    m=f.mean(1,keepdim=True)
    k=f>=m
    def center(mask):
        n=mask.sum(1)
        return torch.where(n>0,(f*mask).sum(1)/n.clamp_min(1),m.squeeze(1))
    lo,hi=center(~k),center(k)
    t=a.permute(0,2,3,1).reshape(-1,c//16,16).transpose(0,1)
    z=(t.sum(-1,keepdim=True)*lo[:,None]+torch.bmm(t,k.to(t.dtype))*(hi-lo)[:,None]).sum(0)
    z=z.reshape(b,h,j,w.shape[1],2,2)
    bias=getattr(module,'bias',None)
    if bias is not None: z=z+bias.reshape(1,1,1,-1,1,1)
    return z.permute(0,3,1,4,2,5).flatten(2,3).flatten(3,4)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 96, 16, 16], [24576, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    cin, cout = params["cin"], params["cout"]
    weight = module.weight.flatten(1).reshape(cin // 16, 16, cout * 4)
    mean = weight.mean(dim=1, keepdim=True)
    upper = weight >= mean

    def centroid(mask):
        count = mask.sum(dim=1, keepdim=True)
        return torch.where(count > 0, (weight * mask).sum(dim=1, keepdim=True)
                           / count.clamp_min(1), mean)

    lo, hi = centroid(~upper), centroid(upper)
    # Distribute the two sums offline: each input contributes exactly its
    # selected centroid. The runtime dot never rounds an intermediate sum.
    projected = torch.where(upper, hi, lo).reshape(cin, cout, 4).permute(2, 0, 1)
    bias = getattr(module, "bias", None)
    if bias is None:
        bias = weight.new_zeros(cout)
    rows = weight.new_zeros(4, cin + 1, 128)
    rows[:, 0, :cout] = bias
    rows[:, 1:, :cout] = projected
    # Keep a leading term on the e2m5 row grid and store the correction
    # in a separate row, where it gets its own, finer scale.
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 6)
    leading = torch.trunc(rows / step) * step
    return {"coeff": torch.stack((leading, rows - leading), dim=-2).reshape(-1, 128)}
