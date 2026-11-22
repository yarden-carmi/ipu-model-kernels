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
    weight=module.weight
    rank=weight.shape[0]//3
    p,q,r,s=weight.double().flatten(2).unbind(-1)
    d=(p-q-r+s)*0.5
    u,sig,vh=torch.linalg.svd(d,full_matrices=False)
    f=x.float().movedim(-3,-1)
    A=f@((p+q+r+s)*0.5).float()
    B=f@((p-q+r-s)*0.5).float()
    C=f@((p+q-r-s)*0.5).float()
    D=(f@u[:,:rank].float())@((sig[:rank,None]*vh[:rank]).float())
    y=torch.stack((A+B+C+D,A-B+C-D,A+B-C-D,A-B-C+D),dim=-1)*0.5+module.bias.float().unsqueeze(-1)
    h,w=x.shape[-2:]
    o=weight.shape[1]
    n=x.ndim-3
    return y.reshape(*x.shape[:-3],h,w,o,2,2).permute(*range(n),n+2,n,n+3,n+1,n+4).reshape(*x.shape[:-3],o,2*h,2*w).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 96, 16, 16], [24576, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, *, rank, **params):
    p, q, r, s = module.weight.double().flatten(2).unbind(-1)
    u, sigma, vh = torch.linalg.svd((p - q - r + s) * 0.5, full_matrices=False)
    # Include the inverse Haar's common factor of 1/2 in the output-side weights.
    blocks = ((p + q + r + s) * 0.25,
              (p - q + r - s) * 0.25,
              (p + q - r - s) * 0.25,
              u[:, :rank] * sigma[:rank],
              vh[:rank] * 0.5,
              module.bias.reshape(1, -1))
    rows = torch.cat([torch.nn.functional.pad(b.float(), (0, 128 - b.shape[1]))
                      for b in blocks])
    # Two row-scaled pieces keep the coefficient rounding error below the
    # output rounding error even when the signed Haar modes cancel.
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[:, :1]), exponent - 6)
    hi = (rows / step).round() * step
    return {"coeff": torch.stack((hi, rows - hi), dim=1).flatten(0, 1)}
