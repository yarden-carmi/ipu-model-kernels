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
    """Lay out bias then [ky, input channel, kx] coefficient expansions."""
    weight = module.weight.detach().double()
    cout, per_group, _, _ = weight.shape
    groups = params['groups']
    dense = weight.new_zeros((cout, groups * per_group, 3, 3))
    for group in range(groups):
        outputs = slice(group * (cout // groups), (group + 1) * (cout // groups))
        channels = slice(group * per_group, (group + 1) * per_group)
        dense[outputs, channels] = weight[outputs]
    bias = module.bias.detach().double() if params['bias'] else weight.new_zeros(cout)
    coeff = torch.cat((bias[:, None], dense.transpose(1, 2).reshape(cout, -1)), dim=1)
    _, exponent = torch.frexp(coeff.abs())
    parts = []
    # Three row-scaled digits retain roughly 15 bits of each coefficient.
    for part in range(3):
        step = torch.exp2(exponent.double() - 5 * (part + 1))
        piece = (coeff / step).round().clamp(-31, 31) * step
        parts.append(piece)
        coeff = coeff - piece
    chunks = (params['in0_d3'] + 127) // 128
    packed = torch.stack(parts, dim=-1)[:, None, :, :, None].expand(-1, chunks, -1, -1, 128).clone()
    packed[:, 0, 1::3, :, 0] = 0
    packed[:, -1, 3::3, :, (params['in0_d3'] - 1) % 128] = 0
    return {'weights': torch.cat((weight.new_zeros((1, 128)), packed.reshape(-1, 128)))}
