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
 x=inputs[0]
 w,b=module.weight,getattr(module,'bias',None)
 ci,co,kh,kw=w.shape
 n,_,h,s=x.shape
 g,r=co//8,5*kh*kw
 a=w.permute(1,2,3,0).reshape(g,8*kh*kw,ci).double()
 u,d,v=torch.linalg.svd(a,full_matrices=False)
 z=torch.einsum('nihw,gri->ngrhw',x,v[:,:r].to(x.dtype))
 y=torch.einsum('ngrhw,gpr->ngphw',z,(u[:,:,:r]*d[:,None,:r]).to(x.dtype)).reshape(n,co,kh,kw,h,s)
 if b is not None: y=y+b.reshape(1,co,1,1,1,1)
 return y.permute(0,1,4,2,5,3).reshape(n,co,h*kh,s*kw)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 96, 16, 16], [24576, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, *, rank, **params):
    w = module.weight
    ci, co, kh, kw = w.shape
    groups = co // 8
    pack = 128 // rank
    blocks = (groups + pack - 1) // pack
    matrix = w.permute(1, 2, 3, 0).reshape(groups, 8 * kh * kw, ci)
    u, sigma, vh = torch.linalg.svd(matrix.double(), full_matrices=False)

    # Put several groups' latent coordinates in one projection row.
    lhs = w.new_zeros(blocks, ci, 128)
    rhs = w.new_zeros(kh, kw, groups, rank, 128)
    lifted = (u[..., :rank] * sigma[:, None, :rank]).reshape(groups, 8, kh, kw, rank)
    for g in range(groups):
        block, slot = divmod(g, pack)
        lhs[block, :, slot * rank:(slot + 1) * rank] = vh[g, :rank].T
        rhs[:, :, g, :, 8*g:8*(g+1)] = lifted[g].permute(1, 2, 3, 0)

    bias = w.new_zeros(1, 128)
    if getattr(module, 'bias', None) is not None:
        bias[0, :co] = module.bias
    rows = torch.cat([lhs.reshape(-1, 128)] + [
        part for phase in rhs.flatten(0, 1) for part in (bias, phase.reshape(-1, 128))
    ]).float()
    # Keep the coarse component representable even if rounding crosses a power of two.
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[:, :1]), exponent - 5)
    hi = (rows / step).round() * step
    return {'coeff': torch.stack((hi, rows - hi), dim=1).flatten(0, 1)}
