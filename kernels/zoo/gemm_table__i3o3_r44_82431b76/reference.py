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
    r0 = aten.conv2d.default(_v(ins[0], [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 384, 32, 32], [393216, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 384, 32, 32], [393216, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 384, 32, 32])}
# ---- end of the frozen reference ----


def _digits(rows):
    """Split row-scaled coefficients into a coarse term and a residual."""
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 4)
    coarse = torch.round(rows / step) * step
    return torch.stack((coarse, rows - coarse), dim=-2)


def fold(module, **params):
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
        bias = weight.new_zeros(n)

    small = k <= 16
    tight = 18 <= k <= 32 and k % 2 == 0
    groups = (k - 2) // 2 if tight else min((k + 3) // 4, (k - 1) // 2) if small else k // 4 if k <= 64 else (k - 1) // 2
    paired = k - 2 * groups
    blocks = (paired + 31) // 32
    rows = weight.new_zeros(n, blocks, 128)
    rows[:, :, :32] = torch.nn.functional.pad(weight[:, :paired], (0, blocks * 32 - paired)).reshape(n, blocks, 32)
    if k <= 32:
        rows[:, 0, 127] = bias
    packed = _digits(rows).reshape(n, -1, 128)
    if tight:
        packed = packed[:, :0]
    if k > 32 or tight:
        packed = torch.cat((_digits(bias[:, None].expand(n, 128)), packed), dim=1)
    if small and groups:
        tail = weight.new_zeros(n, groups, 128)
        tail[..., 0] = weight[:, paired::2]
        tail[..., 127] = weight[:, paired + 1::2]
        packed = torch.cat((packed, tail), dim=1)
    elif groups:
        for start in range(paired, k, 64):
            pair = weight[:, start:start + 64].reshape(n, -1, 2)
            _, exponent = torch.frexp(pair.abs().amax(dim=(1, 2), keepdim=True))
            step = torch.ldexp(torch.ones_like(exponent, dtype=pair.dtype), exponent - 6)
            a, b = pair.unbind(-1)
            s = step.squeeze(-1)
            # Choose a small common correction on the coefficient grid. The
            # unrounded remainder still goes in the table for FP32 execution.
            scale = s * 32
            grid = torch.arange(-64, 65, dtype=pair.dtype, device=pair.device)
            candidates = s.unsqueeze(-1) * grid / 32
            def error(w):
                v = (w.unsqueeze(-1) - candidates).abs()
                _, e = torch.frexp(v)
                quantum = torch.maximum(torch.ldexp(torch.ones_like(v), e - 6), s.unsqueeze(-1) / 8)
                rounded = torch.minimum(torch.round(v / quantum) * quantum, (scale * (63 / 32)).unsqueeze(-1))
                return rounded - v
            ea, eb = error(a), error(b)
            loss = ea.square() + eb.square() + candidates.square() / 4096
            if tight:
                # The first shared residual also covers the cached prefix.
                for extra in weight[:, :2].unbind(-1):
                    loss[:, :1] += error(extra[:, None]).square()
            correction = candidates.expand_as(loss).gather(-1, loss.argmin(dim=-1, keepdim=True)).squeeze(-1)
            tail = weight.new_zeros(n, 2, 128)
            count = a.shape[1]
            if tight:
                tail[:, 0, :2] = weight[:, :2] - correction[:, :1]
                tail[:, 0, 2:2 + 2 * count:2] = a - correction
                tail[:, 0, 3:2 + 2 * count:2] = b - correction
            else:
                tail[:, 0, :count] = a - correction
                tail[:, 0, 64:64 + count] = b - correction
            tail[:, 0, 127] = scale.flatten()
            tail[:, 1, :count] = correction
            packed = torch.cat((packed, tail), dim=1)
    return {'coeff': torch.nn.functional.pad(packed.reshape(-1, 128), (0, 0, 0, 1))}
