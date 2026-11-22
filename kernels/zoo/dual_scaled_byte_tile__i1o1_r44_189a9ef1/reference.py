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
    xf,wf = x.float(),module.weight.float()
    sx = xf.abs().amax(-3,keepdim=True)/127
    sw = wf.abs().amax(0,keepdim=True)/127
    sx = torch.where(sx==0,1.,sx)
    sw = torch.where(sw==0,1.,sw)
    qx = (xf/sx).round().clamp(-127,127).double()
    qw = (wf/sw).round().clamp(-127,127).double()
    y = torch.einsum('...ihw,ioab->...ohawb',qx,qw).float()
    y = y * sx.unsqueeze(-1).unsqueeze(-3) * sw.squeeze(0)[:,None,:,None,:]
    b = getattr(module,'bias',None)
    if b is not None:
        y = y + b.float().reshape(-1,1,1,1,1)
    return y.flatten(-2).flatten(-3,-2).to(x.dtype)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 48, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.weight.float()
    cin, cout, kh, kw = weight.shape
    scale = weight.abs().amax(0) / 127
    scale = torch.where(scale == 0, 1., scale)
    byte = (weight / scale).round().clamp(-127, 127)
    byte = byte.permute(2, 3, 1, 0).reshape(-1, cin)

    def pad(x):
        return torch.nn.functional.pad(x, (0, 128 - x.shape[-1]))

    def split(x):
        # Each component fits a shared-exponent row without losing any bits.
        parts = []
        for _ in range(3):
            exponent = torch.frexp(x.abs().amax(-1, keepdim=True))[1]
            step = torch.ldexp(torch.ones_like(exponent, dtype=x.dtype), exponent - 7)
            part = (x / step).trunc() * step
            parts.append(part)
            x = x - part
        return torch.stack(parts, dim=-2)

    bias = getattr(module, 'bias', None)
    if bias is None:
        bias = weight.new_zeros(cout)
    phase = scale.permute(1, 2, 0).reshape(-1, cout) / 127
    coeff = pad(split(torch.cat((bias.float()[None], phase))).flatten(0, 1))
    controls = coeff.new_tensor([127 / 128, 1 / 128, 12582912., 2. ** -30])[:, None].expand(-1, 128)
    return {'weight': pad(byte), 'coeff': torch.cat((controls, coeff))}
