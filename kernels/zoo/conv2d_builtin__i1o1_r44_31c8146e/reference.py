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
    import types
    ins = tuple(t.clone() for t in ins)  # an in-place operation below writes on its own copies
    module = types.SimpleNamespace(**{k: v.clone() if hasattr(v, 'clone') else v
                                      for k, v in vars(module).items()})
    r0 = aten.conv2d.default(_v(ins[0], [1, 1, 224, 224], [150528, 50176, 224, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op0, [1, 64, 224, 224], [3211264, 50176, 224, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 64, 224, 224])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Output-lane vectors in bias, tap, input-channel order per block."""
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

    rows = weight.new_zeros((blocks, 1 + kh * kw * cin, 128))
    rows[:, 1:] = dense.reshape(blocks, 128, cin, kh, kw).permute(
        0, 3, 4, 2, 1).reshape(blocks, -1, 128)
    if params['bias']:
        for block in range(blocks):
            bias = module.bias[128 * block:128 * (block + 1)]
            rows[block, 0, :bias.numel()] = bias

    # High part and residual get separate shared row scales.
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    return {'weights': torch.stack((hi, rows - hi), dim=2).reshape(blocks, -1, 128)}
