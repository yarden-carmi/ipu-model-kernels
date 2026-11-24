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
    """Expand each grouped horizontal span and split it into two NX8 rows."""
    weight = module.weight.detach().to(torch.float64)
    cout, per_group, kh, kw = weight.shape
    groups = params['groups']
    cin = groups * per_group
    dense = weight.new_zeros((cout, cin, kh, kw))
    for group in range(groups):
        outputs = slice(group * (cout // groups), (group + 1) * (cout // groups))
        inputs = slice(group * per_group, (group + 1) * per_group)
        dense[outputs, inputs] = weight[outputs]
    segments = (kw * cin + 127) // 128
    taps = weight.new_zeros((kh, cout, segments * 128))
    taps[..., :kw * cin] = dense.permute(2, 0, 3, 1).reshape(kh, cout, kw * cin)
    if cin == 64:
        # Pair the otherwise half-empty rightmost segments of the first two taps.
        wide = taps[..., :128]
        right = taps[..., 128:192]
        taps = torch.cat((wide, torch.cat((right[0], right[1]), dim=-1)[None],
                          torch.nn.functional.pad(right[2], (0, 64))[None]), dim=0)
    bias_row = weight.new_zeros((1, 128))
    if params['bias']:
        bias_row[0, :cout] = module.bias
    rows = torch.cat((bias_row, taps.reshape(-1, 128)))
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    return {'weights': torch.cat((weight.new_zeros((1, 128)),
                                  torch.stack((hi, rows - hi), dim=1).reshape(-1, 128)))}
