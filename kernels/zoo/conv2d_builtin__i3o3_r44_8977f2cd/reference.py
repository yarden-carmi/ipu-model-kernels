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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 16, 16], [16384, 256, 16, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 16, 16, 16], [4096, 256, 16, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 16, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold border masks into the spatial vectors, with two residual parts."""
    weight = module.weight.detach().double()
    cout, cin = weight.shape[:2]
    h, w = params['in0_d2'], params['in0_d3']
    pack = max(1, 128 // w)
    if h % pack:
        pack = 1
    blocks, chunks = h // pack, (w + 127) // 128
    variants = [0] if blocks == 1 else ([0, 1] if blocks == 2 else [0, 1, blocks - 1])
    coeff = weight.new_zeros((cout, 1 + 9 * cin))
    if params['bias']:
        coeff[:, 0] = module.bias
    coeff[:, 1:] = weight.reshape(cout, -1)

    _, exponent = torch.frexp(coeff.abs())
    parts = []
    for i in range(2):
        step = torch.exp2(exponent.double() - 5 * (i + 1))
        part = (coeff / step).round().clamp(-31, 31) * step
        parts.append(part)
        coeff = coeff - part
    parts.append(coeff)
    coeff = torch.stack(parts, dim=-1)

    lane = torch.arange(128, device=weight.device)
    taps = torch.arange(9, device=weight.device)
    masks = []
    for c in range(chunks):
        x = lane % w if pack > 1 else c * 128 + lane
        for block in variants:
            y = block * pack + (lane // w if pack > 1 else torch.zeros_like(lane))
            valid = (x < w) & (y < (block + 1) * pack)
            xx, yy = x + taps[:, None] % 3 - 1, y + taps[:, None] // 3 - 1
            mask = valid & (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
            masks.append(torch.cat((valid[None], mask.repeat(cin, 1))))
    mask = torch.stack(masks).reshape(chunks, 1, len(variants), 1 + 9 * cin, 1, 128)
    return {'weights': coeff[None, :, None, :, :, None] * mask}
