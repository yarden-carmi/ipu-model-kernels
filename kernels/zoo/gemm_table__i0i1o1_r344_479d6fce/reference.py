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
    r0 = aten.conv2d.default(_v(ins[0], [1, 192, 16, 16], [49152, 256, 16, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 128, 16, 16], [32768, 256, 16, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 128, 16, 16], [32768, 256, 16, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    r0 = aten.cat.default([_v(ins[1], [1, 128, 16, 16], [32768, 256, 16, 1], 0), _v(op2, [1, 128, 16, 16], [32768, 256, 16, 1], 0)], 1)
    op3 = _pick(r0, 0)  # step 0
    return {"out0": _out(op3, [1, 256, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    def split(rows):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(rows[..., :1]), exponent - 4)
        coarse = torch.round(rows / step) * step
        return torch.stack((coarse, rows - coarse), dim=-2).contiguous()

    n, k = params['n'], params['k']
    start = n % 128
    end = (-(start + n)) % 128
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    rows = torch.nn.functional.pad(weight.T, (start, end)).reshape(k, -1, 128)
    groups = params['in0_d0']
    # Consecutive taps in a group share a physical input row.
    rows = rows.reshape(groups, k // groups, -1, 128)
    result = {'w': split(rows.permute(2, 1, 0, 3).reshape(-1, k, 128))}
    if params['bias']:
        bias = module.op1_bias - module.op1_running_mean * scale
        result['b'] = split(torch.nn.functional.pad(bias, (start, end)).reshape(-1, 128))
    return result
