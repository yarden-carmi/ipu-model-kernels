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
    r0 = aten.conv2d.default(_v(ins[0], [1, 192, 16, 16], [49152, 256, 16, 1], 0), module.weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.weight
    co, ci, kh, kw = weight.shape
    taps = weight.permute(0, 2, 1, 3).reshape(co, -1) * (2.0 ** -16)
    panels = torch.nn.functional.pad(taps, (0, (-taps.shape[1]) % 128)).reshape(co, -1, 128)
    seed = weight.new_zeros((co, 1, 128))
    if params.get("bias"):
        bias = getattr(module, "bias_vec", None)
        if bias is None:
            bias = module.bias
        seed[:, 0, :] = bias.reshape(-1, 1)
    ow = params['out0_d3']
    out_pack = (4 if ow <= 32 else 2 if ow <= 64 else 1) if params['stride'] == 1 else 1
    masks = weight.new_zeros((1 + 3 * out_pack, 128))
    x = torch.arange(128, device=weight.device)
    for kx in range(kw):
        ix = x + kx - params['padding']
        valid = (ix >= 0) & (ix < params['in0_d3'])
        if out_pack == 1:
            masks[kx + 1] = valid * (2.0 ** 16)
        else:
            for half in range(out_pack):
                masks[kx + 1 + 3 * half, half * ow:(half + 1) * ow] = valid[:ow] * (2.0 ** 16)
    return {"weights": torch.cat((seed, panels), dim=1).reshape(-1, 128), "masks": masks}
