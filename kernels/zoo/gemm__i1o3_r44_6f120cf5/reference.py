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
    r0 = aten.conv2d.default(_v(ins[0], [1, 72, 28, 28], [56448, 784, 28, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 24, 28, 28], [18816, 784, 28, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 24, 28, 28])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch norm and split each coefficient row into digits."""
    n, k = params['n'], params['k']
    width = params['out0_d3']
    pack = min(4 + 124 * max(0, 2 - params['m']), 128 // width)
    weight = module.op0_weight.detach().double().reshape(n, k)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.detach().double().reshape(n) * torch.rsqrt(
            module.op1_running_var.detach().double().reshape(n) + 1e-5)
        bias = module.op1_bias.detach().double().reshape(n) - scale * module.op1_running_mean.detach().double().reshape(n)
        if getattr(module, 'op0_bias', None) is not None:
            bias = bias + scale * module.op0_bias.detach().double().reshape(n)
        weight = weight * scale[:, None]
    else:
        b = getattr(module, 'op0_bias', getattr(module, 'bias', None))
        bias = weight.new_zeros(n) if b is None else b.detach().double().reshape(n)
    if not params['bias']:
        bias = torch.zeros_like(bias)

    def digits(rows):
        exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
        step = torch.ldexp(torch.ones_like(rows[..., :1]), exp - 3)
        parts = []
        for _ in range(4):
            digit = (rows / step).round() * step
            parts.append(digit)
            rows = rows - digit
            step = step / 16
        return torch.stack(parts, dim=-2).reshape(-1, 128)

    weights = torch.nn.functional.pad(weight, (0, (-k) % 128)).reshape(n, -1, 128)
    stream = []
    for start in range(0, n, pack):
        end = min(start + pack, n)
        b = bias[start:end].repeat_interleave(width)
        stream.append(digits(torch.nn.functional.pad(b, (0, 128 - b.numel()))))
        stream.append(digits(weights[start:end]))
    return {'coeff': torch.cat(stream).float()}
