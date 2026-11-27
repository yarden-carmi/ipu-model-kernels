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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 128, 128], [262144, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 64, 128, 128], [1048576, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 64, 128, 128], [1048576, 16384, 128, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 64, 128, 128])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch normalization and split coefficients into two digits."""
    n, k = params['n'], params['k']
    source = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    weight = source.double().reshape(n, k)
    source_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weight.new_zeros(n) if source_bias is None else source_bias.double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None]
        bias = (bias - module.op1_running_mean.double()) * scale + module.op1_bias.double()
    if not params['bias']:
        bias = torch.zeros_like(bias)

    blocks = (k + 31) // 32
    rows = weight.new_zeros(n, 1 + blocks, 128)
    rows[:, 0, 0] = bias
    rows[:, 1:, :32] = torch.nn.functional.pad(weight, (0, 32 * blocks - k)).reshape(n, blocks, 32)
    if k <= 16:
        sizes = [2, 2, 3, 3, 3, 3] if k == 16 else [min(3, k - i) for i in range(0, k, 3)]
        main, fine = torch.zeros_like(rows[:, 0]), torch.zeros_like(rows[:, 0])
        _, exp = torch.frexp(weight.abs().amax(1, keepdim=True))
        scale = torch.ldexp(torch.ones_like(exp, dtype=weight.dtype), exp - 1)
        main[:, 127] = scale[:, 0]
        grid = torch.arange(-256, 257, dtype=weight.dtype, device=weight.device)
        fine_scale = scale / 64
        v = grid * fine_scale / 256
        _, ve = torch.frexp(v.abs())
        vstep = torch.maximum(torch.ldexp(torch.ones_like(v), ve - 7), fine_scale / 64)
        candidates = (v / vstep).round() * vstep
        # Choose a shared correction so the remaining weights land near the NX8 grid.
        start = 0
        for g, taps in enumerate(weight.split(sizes, dim=1)):
            mag = (taps.unsqueeze(-1) - candidates[:, None, :]).abs()
            _, e = torch.frexp(mag)
            quantum = torch.maximum(torch.ldexp(torch.ones_like(mag), e - 7), scale[:, :, None] / 64)
            rounded = torch.minimum((mag / quantum).round() * quantum, scale[:, :, None] * (2 - 1 / 64))
            loss = (rounded - mag).square().sum(1) + candidates.square() / 4096
            common = candidates.gather(1, loss.argmin(1, keepdim=True))
            main[:, start:start + taps.size(1)] = taps - common
            fine[:, g] = common[:, 0]
            start += taps.size(1)
        _, ef = torch.frexp(torch.maximum(fine.abs().amax(1, keepdim=True), scale / 64))
        fine[:, 126] = torch.ldexp(torch.ones_like(scale), ef - 1)[:, 0]
        return {'coeff': torch.nn.functional.pad(torch.stack((rows[:, 0], main, fine), dim=1).reshape(-1, 128), (0, 0, 0, 1))}
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - (6 if k <= 16 else 5))
    coarse = torch.round(rows / step) * step
    return {'coeff': torch.stack((coarse, rows - coarse), dim=2).reshape(-1, 128)}
