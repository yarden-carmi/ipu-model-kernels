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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 224, 224], [3211264, 50176, 224, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op0, [1, 8, 224, 224], [401408, 50176, 224, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 8, 224, 224])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Bias vectors and channel dot-product rows, in output-block order."""
    weight = module.weight.detach().to(torch.float64)
    cout, per_group, kh, kw = weight.shape
    groups = params['groups']
    per_output_group = cout // groups
    dense = weight.new_zeros((kh, kw, cout, 128))
    for group in range(groups):
        outputs = slice(group * per_output_group, (group + 1) * per_output_group)
        inputs = slice(group * per_group, (group + 1) * per_group)
        dense[:, :, outputs, inputs] = weight[outputs].permute(2, 3, 0, 1)

    blocks = []
    for start in range(0, cout, 128):
        stop = min(start + 128, cout)
        bias = weight.new_zeros((1, 128))
        if params['bias']:
            bias[0, :stop - start] = module.bias[start:stop]
        blocks.append(bias)
        blocks.append(dense[:, :, start:stop].reshape(-1, 128))
    rows = torch.cat(blocks)
    # Give the residual its own row scale to preserve small coefficients.
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.exp2(exponent.to(rows.dtype) - 6)
    hi = rows.sign() * (rows.abs() / step + 0.5).floor().clamp(max=63) * step
    return {'weights': torch.stack((hi, rows - hi), dim=1).reshape(-1, 128)}
