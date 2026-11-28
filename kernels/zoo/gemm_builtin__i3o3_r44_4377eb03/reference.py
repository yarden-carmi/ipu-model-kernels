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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 72, 56, 56], [225792, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 72, 56, 56], [225792, 3136, 56, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 72, 56, 56])}
# ---- end of the frozen reference ----


def fold(module, **params):
    n, k = params['n'], params['k']
    weights = getattr(module, 'op0_weight', getattr(module, 'weight', None)).detach().double().reshape(n, k)
    source_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weights.new_zeros(n) if source_bias is None else source_bias.detach().double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = weights * scale[:, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
    rows = torch.cat((bias[:, None], weights), dim=1).reshape(-1, 1).expand(-1, 128)
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[:, :1]), exponent - 4)
    high = torch.round(rows / step) * step
    return {'coeff': torch.stack((high, rows - high), dim=1).reshape(-1, 128)}
    """Fold row-dot panels or packed spatial channel diagonals."""
    n, k = params['n'], params['k']
    source = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    weights = source.detach().double().reshape(n, k)
    source_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weights.new_zeros(n) if source_bias is None else source_bias.detach().double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = weights * scale[:, None]
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
    if not params['bias']:
        bias = weights.new_zeros(n)

    blocks = (n + 127) // 128
    if (params['m'] == 1 and params['in0_d0'] * params['in0_d2'] * params['in0_d3'] == 1
            and k == params['in0_d1']):
        chunks = (k + 127) // 128
        panels = torch.nn.functional.pad(weights, (0, chunks * 128 - k)).reshape(n, chunks, 128)
        packed = []
        for start in range(0, n, 128):
            end = min(start + 128, n)
            b = torch.nn.functional.pad(bias[start:end], (0, 128 - end + start))
            packed.extend((b.reshape(1, 128), panels[start:end].reshape(-1, 128)))
        rows = torch.cat(packed)
    else:
        width = params['in0_d3']
        pack = min(4, 128 // width)
        packed = []
        for o in range(0, n, pack):
            b = weights.new_zeros((1, 128))
            for g in range(min(pack, n - o)):
                b[0, g * width:(g + 1) * width] = bias[o + g]
            _, exponent = torch.frexp(b.abs().amax())
            step = torch.ldexp(torch.ones_like(b), exponent - 4)
            high = torch.round(b / step) * step
            packed.extend((high, b - high))
            for i in range(0, k, pack):
                for shift in range(1 - pack, pack):
                    row = weights.new_zeros((1, 128))
                    for g in range(min(pack, n - o)):
                        source = g + shift
                        if 0 <= source < min(pack, k - i):
                            row[0, g * width:(g + 1) * width] = weights[o + g, i + source]
                    if pack == 2 and shift <= 0:
                        _, exponent = torch.frexp(row.abs().amax())
                        step = torch.ldexp(torch.ones_like(row), exponent - 4)
                        high = torch.round(row / step) * step
                        packed.extend((high, row - high))
                    else:
                        packed.append(row)
        return {'coeff': torch.cat(packed)}
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(rows[..., :1]), exp - 4)
    high = torch.round(rows / step) * step
    return {'coeff': torch.stack((high, rows - high), dim=-2).reshape(-1, 128)}
