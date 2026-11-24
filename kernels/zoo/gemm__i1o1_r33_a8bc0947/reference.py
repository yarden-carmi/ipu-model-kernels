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
    r0 = aten.linear.default(_v(ins[0], [1, 64, 512], [32768, 512, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 64, 512])}
# ---- end of the frozen reference ----


def fold(module, **params):
    def digits(x):
        _, exponent = torch.frexp(x.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(x[..., :1]), exponent - 4)
        high = (x / step).round() * step
        residual = x - high
        step = step / 16
        middle = (residual / step).round() * step
        return torch.stack((high, middle, residual - middle), dim=-2)

    n, k = params['n'], params['k']
    pairs, chunks = (n + 1) // 2, (k + 127) // 128
    weight = module.weight.detach().double()
    padded = weight.new_zeros((2 * pairs, 128 * chunks))
    padded[:n, :k] = weight
    rows = digits(padded.reshape(pairs, 2, chunks, 128)).permute(0, 2, 3, 1, 4).reshape(-1, 128)
    result = {'w': rows}
    if params['bias']:
        width = params['out0_d1']
        bias = module.bias.detach().double()
        packed = bias.new_zeros((2 * pairs, width))
        packed[:n] = bias[:, None]
        packed = packed.reshape(pairs, 2 * width)
        result['b'] = digits(torch.nn.functional.pad(packed, (0, 128 - 2 * width))).reshape(-1, 128)
    return result
