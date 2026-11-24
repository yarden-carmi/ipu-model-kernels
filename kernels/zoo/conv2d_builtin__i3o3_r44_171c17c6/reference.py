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
    r0 = aten.conv2d.default(_v(ins[0], [1, 88, 28, 28], [68992, 784, 28, 1], 0), module.op0_weight, None, [1, 1], [1, 1], [1, 1], 88)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 88, 28, 28], [68992, 784, 28, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 88, 28, 28], [68992, 784, 28, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 88, 28, 28])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold the inference affine transform, then split coefficients into NX8 digits."""
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double() * scale[:, None, None, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = getattr(module, 'weight', getattr(module, 'op0_weight', None)).double()
        bias = getattr(module, 'bias', getattr(module, 'op0_bias', None))
        bias = weight.new_zeros(weight.shape[0]) if bias is None else bias.double()

    coefficients = torch.cat((bias[:, None], weight.flatten(1)), dim=1)
    _, exponent = torch.frexp(coefficients)
    digits = []
    for i in (1, 2):
        step = torch.exp2(exponent.double() - 5 * i)
        part = (coefficients / step).round().clamp(-31, 31) * step
        digits.append(part)
        coefficients = coefficients - part
    digits.append(coefficients)

    lane = torch.arange(128, device=weight.device)
    x = lane * params['stride']
    dx = (torch.arange(weight[0].numel(), device=weight.device) % 3 - 1)[:, None]
    masks = (x + dx >= 0) & (x + dx < params['in0_d3']) & (lane < params['out0_d3'])
    masks = torch.cat(((lane < params['out0_d3'])[None], masks))
    return {'weights': (torch.stack(digits, dim=-1)[..., None] * masks[None, :, None]).flatten(1, 2)}
