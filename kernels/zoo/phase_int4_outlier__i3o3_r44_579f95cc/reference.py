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
    x, weight = inputs[0], module.weight
    bias = getattr(module,'bias',None)
    i,o,a,b = weight.shape
    n,_,h,w = x.shape
    k = weight.float().reshape(i,o*a*b)
    t = x.float().permute(0,2,3,1).reshape(-1,i)
    j = t.abs().argmax(-1,keepdim=True)
    outlier = t.gather(1,j)
    t = t.scatter(1,j,0.0)
    sx = t.abs().amax(-1,keepdim=True)/7
    sw = k.abs().amax(0,keepdim=True)/7
    sx = torch.where(sx>0,sx,1.0)
    sw = torch.where(sw>0,sw,1.0)
    y = ((t/sx).round().clamp(-7,7) @ (k/sw).round().clamp(-7,7))*sx*sw + outlier*k[j[:,0]]
    y = y.reshape(n,h,w,o,a,b)
    if bias is not None:
        y = y+bias.float().reshape(1,1,1,o,1,1)
    return y.permute(0,3,1,4,2,5).reshape(n,o,h*a,w*b).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 48, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    w = module.weight.float().permute(2, 3, 0, 1)
    kh, kw, cin, cout = w.shape
    bias = getattr(module, 'bias', None)
    if bias is None:
        bias = w.new_zeros(cout)
    scale = w.abs().amax(dim=2, keepdim=True) / 7
    scale = torch.where(scale > 0, scale, 1)
    q = (w / scale).round().clamp(-7, 7)

    def split(v):
        _, exponent = torch.frexp(v.abs().amax(dim=-1, keepdim=True))
        hi = torch.ldexp(torch.trunc(torch.ldexp(v, 6 - exponent)), exponent - 6)
        return hi, v - hi

    wh, wl = split(w)
    sh, sl = split(scale / 7)
    bh, bl = split(bias.float().expand(kh, kw, 1, cout))
    correction = torch.stack((wh, wl), dim=3).flatten(2, 3)
    rows = torch.cat((q, correction, sh, sl, bh, bl), dim=2).reshape(-1, cout)
    helpers = w.new_zeros((5, 128))
    helpers[0, :5] = torch.tensor([1, -1, 5, 0, 6])
    helpers[1, :14] = torch.tensor([1, -1, 14, -14, 1, 3, 5, 7, 9, 11, 13, 39, 57, 64]) * (2.0 ** 48)
    helpers[2, :cin] = torch.arange(cin, 0, -1)
    helpers[3, 0] = 1 / 64
    significands = torch.arange(32, 64, dtype=torch.float32)
    below_half = ((significands * 0.5) / (significands / 7)).round() < 4
    # At a power of two, the step below the maximum is half as large.
    factors = significands.clone()
    factors[0] = 64
    helpers[4, :32] = torch.where(below_half, factors, 0) * (2.0 ** 48)
    return {"helpers": helpers, "weights": torch.nn.functional.pad(rows, (0, 128 - cout))}
