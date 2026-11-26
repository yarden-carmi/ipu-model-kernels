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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 256, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    n, k = params['n'], params['k']
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    if not params['bias']:
        bias = torch.zeros_like(bias)

    # Each tile stores bias first, then an output-channel vector per input tap.
    rows = torch.cat((bias[None, :], weight.T), dim=0)
    rows = torch.nn.functional.pad(rows, (0, (-n) % 128))
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 4)
    coarse = torch.round(rows / step) * step
    if k <= 128:
        # A group uses one correction times the sum of its input taps, then
        # one adjusted weight per tap. In exact arithmetic this equals GEMM.
        _, elem_exp = torch.frexp(rows.abs())
        grid = torch.ldexp(torch.ones_like(rows), torch.maximum(elem_exp - 1, exponent - 3) - 5)
        bias_step = torch.ldexp(torch.ones_like(exponent[:, :1]), exponent[:, :1] - 6)
        hi = (rows[:, :1] / bias_step).round().clamp(-63, 63) * bias_step if k <= 16 else coarse[:, :1]
        tiles = [hi, rows[:, :1] - hi]
        size = 2 if k < 32 or k == 128 else 3
        grouped_k = k - (8 if k == 32 else 0)
        for start in range(0, grouped_k, size):
            w = rows[:, start + 1:start + size + 1]
            if w.shape[1] < size:
                tiles.append(w)
                continue
            g = grid[:, start + 1:start + size + 1]
            r = w - (w / g).round() * g
            anchor = r.gather(1, g.argmax(dim=1, keepdim=True))
            q = ((w - anchor) / g).round() * g
            shared = (w - q).mean(dim=1, keepdim=True)
            # Search offsets on both mantissa grids. A small offset also limits
            # the impact of rounding the staged input sums.
            fine = torch.ldexp(torch.ones_like(g), exponent[:, start + 1:start + size + 1] - 7)
            r1 = w - (w / fine).round() * fine
            trial = torch.cat((shared, r, shared + g, shared - g), dim=1)
            if k <= 32:
                trial = torch.cat((trial, shared * 0, r1, r1 + fine / 2, r1 - fine / 2,
                                   (r1 + r1.mean(dim=1, keepdim=True)) / 2), dim=1)
            if 16 < k <= 32:
                trial = torch.cat((trial, r + g / 4, r - g / 4, r + g / 2, r - g / 2,
                                   (r + shared) / 2), dim=1)
            z = w.unsqueeze(2) - trial.unsqueeze(1)
            re = exponent[:, start + 1:start + size + 1].unsqueeze(2)
            _, ze = torch.frexp(z.abs())
            step = torch.ldexp(torch.ones_like(z), torch.maximum(ze - 1, re - 3) - 5)
            cap = torch.ldexp(torch.ones_like(z), re - 6) * 63
            decoded = ((z / step).round() * step).clamp(-cap, cap)
            step1 = torch.ldexp(torch.ones_like(z), torch.maximum(ze - 1, re - 1) - 6)
            cap1 = torch.ldexp(torch.ones_like(z), re - 7) * 127
            decoded1 = ((z / step1).round() * step1).clamp(-cap1, cap1)
            score = (decoded - z).square().sum(dim=1) + trial.square() / 2048
            if k <= 16:
                score = score + (decoded1 - z).square().sum(dim=1) + trial.square() * (7 / 2048)
            elif k <= 32:
                score = score + trial.square() / 32
            shared = trial.gather(1, score.argmin(dim=1, keepdim=True))
            tiles.extend((shared, w - shared))
        if grouped_k != k:
            w, hi = rows[:, grouped_k + 1:], coarse[:, grouped_k + 1:]
            tiles.append(torch.stack((hi, w - hi), dim=2).flatten(1, 2))
        digits = torch.cat(tiles, dim=1).reshape(-1, 128)
        return {'coeff': torch.nn.functional.pad(digits, (0, 0, 0, 1))}
    digits = torch.stack((coarse, rows - coarse), dim=-2).reshape(-1, 128)
    return {'coeff': torch.nn.functional.pad(digits, (0, 0, 0, 1))}
