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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack vertical taps into 42-channel panels with a residual row each."""
    weight = module.weight.double()
    co, ci, _, _ = weight.shape
    blocks = (ci + 41) // 42
    padded = weight.new_zeros((co, 3, blocks * 42, 3))
    padded[:, :, :ci] = weight.transpose(1, 2)
    panels = weight.new_zeros((co, 3, blocks, 128))
    panels[..., :126] = padded.reshape(co, 3, blocks, 126)

    def split(values):
        _, exponent = torch.frexp(values.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exponent.double() - 6)
        high = (values / step).round().clamp(-63, 63) * step
        return high, values - high

    high, low = split(panels)
    rows = weight.new_zeros((1 + co * (1 + 6 * blocks), 128))
    payload = rows[1:].view(co, 1 + 6 * blocks, 128)
    bias = getattr(module, 'bias', None) if params['bias'] else None
    if bias is not None:
        high_bias, low_bias = split(bias.double().reshape(co, 1))
        payload[:, 0, 0] = high_bias[:, 0]
        payload[:, 0, 1] = low_bias[:, 0]
    payload[:, 1:] = torch.stack((high, low), dim=3).reshape(co, 6 * blocks, 128)
    return {'weights': rows}
