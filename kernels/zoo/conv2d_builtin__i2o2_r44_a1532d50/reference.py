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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 112, 112], [200704, 12544, 112, 1], 0), module.op0_weight, None, [2, 2], [1, 1], [1, 1], 16)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 16, 56, 56], [50176, 3136, 56, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 16, 56, 56])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch norm, then split each coefficient into exact row-scaled digits."""
    scale = module.op1_weight.double() * (module.op1_running_var.double() + 1e-5).rsqrt()
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    weight = module.op0_weight.double() * scale[:, None, None, None]
    cout, icg, _, _ = weight.shape
    oh, ow = params['out0_d2'], params['out0_d3']
    capacity = min(ow, 128 // oh)
    candidate = max(1, ow // ((ow + capacity - 1) // capacity))
    pack = candidate if ow % candidate == 0 else 1

    def digits(coeff):
        _, exponent = torch.frexp(coeff.abs())
        result = []
        for i in range(4):
            step = torch.exp2(exponent.double() - 5 * (i + 1))
            piece = (coeff / step).round().clamp(-31, 31) * step
            result.append(piece)
            coeff = coeff - piece
        return torch.stack(result, dim=-1)

    # Tap order is packed column, horizontal tap, input channel, vertical tap.
    taps = digits(weight.permute(0, 3, 1, 2))
    rows = weight.new_zeros((cout, pack, 3, icg, 3, 4, 128))
    for p in range(pack):
        lo, hi = p * oh, (p + 1) * oh
        rows[:, p, ..., lo:hi] = taps[..., None]
        rows[:, p, :, :, 0, :, lo] = 0
        if (oh - 1) * params['stride'] + 1 >= params['in0_d2']:
            rows[:, p, :, :, 2, :, hi - 1] = 0
    bias_rows = digits(bias)[..., None].expand(-1, -1, 128)
    return {'weights': torch.cat((weight.new_zeros((1, 128)),
                                  torch.cat((bias_rows, rows.reshape(cout, -1, 128)), dim=1)
                                  .reshape(-1, 128)))}
