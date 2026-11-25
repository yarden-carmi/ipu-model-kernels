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
    import torch.nn.functional as F
    x = inputs[0]
    weight, bias = module.weight, getattr(module,'bias',None)
    n,c,h,w = x.shape
    _,o,a,b = weight.shape
    g,p = (c+3)//4,o*a*b
    v = F.pad(weight.float().reshape(c,p).T,(0,4*g-c)).reshape(p,g,4)
    mag, idx = v.abs().sort(dim=-1,descending=True,stable=True)
    cnt = torch.arange(1,5,device=x.device)
    total = mag.cumsum(-1)
    k = (total.square()/cnt).argmax(-1,keepdim=True)
    scale = (total.gather(-1,k)/(k+1)).squeeze(-1)
    keep = torch.zeros_like(v,dtype=torch.bool).scatter(-1,idx,cnt<=k+1)
    bits = 2**(cnt-1)
    pos = ((keep & (v>0))*bits).sum(-1).T
    neg = ((keep & (v<0))*bits).sum(-1).T
    u = F.pad(x.float().permute(0,2,3,1),(0,4*g-c)).reshape(-1,g,4)
    lut = [torch.zeros_like(u[...,0])]
    for j in range(4):
        lut += [u[...,j] if i==0 else q+u[...,j] for i,q in enumerate(lut)]
    L = torch.stack(lut,-1)
    t = ((L.gather(-1,pos.expand(len(u),-1,-1))-L.gather(-1,neg.expand(len(u),-1,-1)))*scale.T).sum(1).reshape(n,h,w,o,a,b)
    if bias is not None:
        t = t + bias.float().reshape(1,1,1,o,1,1)
    return t.permute(0,3,1,4,2,5).reshape(n,o,h*a,w*b).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 48, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, *, cin, cout, kh, kw, w, **params):
    import torch.nn.functional as F

    blocks = (cin + 3) // 4
    v = F.pad(module.weight.float().reshape(cin, -1).T,
              (0, 4 * blocks - cin)).reshape(-1, blocks, 4)
    mag, idx = v.abs().sort(dim=-1, descending=True, stable=True)
    count = torch.arange(1, 5, device=v.device)
    total = mag.cumsum(-1)
    k = (total.square() / count).argmax(-1, keepdim=True)
    scale = total.gather(-1, k) / (k + 1)
    keep = torch.zeros_like(v, dtype=torch.bool).scatter(-1, idx, count <= k + 1)
    # Distribute the common scale over the signed subset difference.
    coeff = (v.sign() * keep * scale).reshape(cout, kh, kw, -1)[..., :cin]
    bias = module.bias.float().reshape(cout, 1, 1, 1).expand(-1, kh, kw, 1)
    values = torch.cat((bias, coeff), dim=-1)
    # Lane order matches the packed output: vertical phase, x, horizontal phase.
    values = values.reshape(cout, kh // 2, 2, kw, cin + 1).permute(0, 1, 4, 2, 3)
    values = values.repeat(1, 1, 1, 1, w).flatten(-2)
    _, exponent = torch.frexp(values.abs().amax(dim=-1, keepdim=True))
    digits = torch.ldexp(values.abs(), 20 - exponent).floor().to(torch.int64)
    parts = [torch.ldexp(((digits >> shift) & 31).float() * values.sign(),
                         exponent + shift - 20) for shift in (15, 10, 5, 0)]
    rows = torch.stack(parts, dim=-2).reshape(-1, 2 * w * kw)
    return {"weights": F.pad(rows, (0, 128 - 2 * w * kw))}
