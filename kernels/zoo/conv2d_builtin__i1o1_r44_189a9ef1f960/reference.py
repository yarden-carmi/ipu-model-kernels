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
    r0 = aten.conv2d.default(_v(ins[0], [1, 32, 224, 224], [1605632, 50176, 224, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 32, 224, 224], [1605632, 50176, 224, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 32, 224, 224])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack each tap/input-channel vector into output lanes, high part then residual."""
    weight = module.weight.detach().to(torch.float64)
    cout, per_group, kh, kw = weight.shape
    groups = params['groups']
    cin = groups * per_group
    blocks = (cout + 127) // 128
    dense = weight.new_zeros((blocks * 128, cin, kh, kw))
    out_per_group = cout // groups
    for group in range(groups):
        channels = slice(group * out_per_group, (group + 1) * out_per_group)
        dense[channels, group * per_group:(group + 1) * per_group] = weight[channels]
    packed = cin == 32 and cout <= 32 and params['in0_d3'] % 4 == 0 and params['stride'] == 1
    dot = cout <= 32 and 2 * cout <= cin
    if packed or dot:
        taps = dense[:cout].permute(2, 3, 0, 1)
        if packed:
            taps = taps.permute(0, 2, 1, 3).reshape(kh, 1, cout, kw * cin)
        vectors = weight.new_zeros((1 + taps.numel() // taps.shape[-1], 128))
        vectors[1:, :taps.shape[-1]] = taps.reshape(-1, taps.shape[-1])
        if params['bias']:
            vectors[0, :cout] = module.bias
        hi, lo = _split(vectors)
        planes = torch.stack((hi, lo), dim=1).reshape(-1, 128)
        if packed:
            planes = torch.cat((planes[:2], weight.new_zeros((1, 128)), planes[2:]))
        return {'weights': planes[None]}
    rows = weight.new_zeros((blocks, 1 + kh * kw * cin, 128))
    rows[:, 1:] = dense.reshape(blocks, 128, cin, kh, kw).permute(
        0, 3, 4, 2, 1).reshape(blocks, -1, 128)
    if params['bias']:
        for block in range(blocks):
            bias = module.bias[128 * block:128 * (block + 1)]
            rows[block, 0, :bias.numel()] = bias

    hi, lo = _split(rows)
    return {'weights': torch.stack((hi, lo), dim=2).reshape(blocks, -1, 128)}


def _split(rows):
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    return hi, rows - hi
