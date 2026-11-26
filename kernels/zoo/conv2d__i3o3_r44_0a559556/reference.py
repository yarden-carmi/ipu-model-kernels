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


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    r0 = aten.conv2d.default(_v(ins[0], [1, 384, 16, 16], [98304, 256, 16, 1], 0), module.weight, module.bias, [2, 2], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 384, 8, 8])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Panel the channel reduction and encode its coefficients in two digits."""
    weight = module.weight.detach().double()
    cout, cin, kh, kw = weight.shape
    patch_scale = 2.0 ** 32
    taps = weight.permute(0, 2, 3, 1)
    taps = torch.nn.functional.pad(taps, (0, (-cin) % 128))
    taps = taps.reshape(cout, -1, 128)
    _, exponent = torch.frexp(taps.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.double() - 6)
    high = (taps / step).round().clamp(-63, 63) * step
    digits = torch.stack((high, taps - high), dim=2).reshape(cout, -1, 128)
    bias = module.bias.double() if params['bias'] else weight.new_zeros(cout)
    filters = torch.cat(((bias * patch_scale)[:, None, None].expand(-1, 1, 128), digits), dim=1)

    x = torch.arange(128, device=weight.device)
    masks = []
    for kx in range(kw):
        ix = x + kx - params['padding']
        masks.append((ix >= 0) & (ix < params['in0_d3']) &
                     (x < params['out0_d3'] * params['stride']))
    lift = torch.stack(masks).to(weight.dtype) * patch_scale
    return {'weights': filters.reshape(-1, 128),
            'masks': torch.cat((lift, weight.new_full((1, 128), 1 / patch_scale)))}
