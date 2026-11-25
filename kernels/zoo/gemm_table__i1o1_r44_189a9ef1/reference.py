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
    """Fold inference batch norm and pack coefficients in MAC order."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op0_weight"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weights = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - scale * module.op1_running_mean.double()
        if getattr(module, "op0_bias", None) is not None:
            bias = bias + scale * module.op0_bias.double()
    else:
        weights = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    if bias is None or not params["bias"]:
        bias = weights.new_zeros(n)
    rows = torch.cat((bias.double()[None], weights.T))
    rows = torch.nn.functional.pad(rows, (0, (-n) % 128))
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 6)
    coarse = (rows / step).round().clamp(-63, 63) * step
    if 16 < k < 128:
        packed = [coarse[:, :1], rows[:, :1] - coarse[:, :1]]
        span = 3
        for start in range(0, k, 16):
            end = min(start + 16, k)
            j = start
            if k <= 32:
                prefix = end - start - 3 * (min(12, end - start) // 3)
                for i in range(start + 1, start + prefix + 1):
                    packed.extend((coarse[:, i:i + 1], rows[:, i:i + 1] - coarse[:, i:i + 1]))
                j += prefix
            while j + span <= end:
                w = rows[:, j + 1:j + 1 + span]
                # Subtract one common correction from the three tap rows.
                # Its MAC against the input sum restores all three terms.
                re = exponent[:, j + 1:j + 1 + span]
                _, e = torch.frexp(w.abs())
                g = torch.ldexp(torch.ones_like(w), torch.maximum(e - 1, re - 3) - 5)
                r = w - (w / g).round() * g
                anchor = r.gather(1, g.argmax(dim=1, keepdim=True))
                q = ((w - anchor) / g).round() * g
                common = (w - q).mean(dim=1, keepdim=True)
                trial = torch.cat((common, r, common + g, common - g), dim=1)
                z = w.unsqueeze(2) - trial.unsqueeze(1)
                re = re.unsqueeze(2)
                _, ze = torch.frexp(z.abs())
                grid = torch.ldexp(torch.ones_like(z), torch.maximum(ze - 1, re - 3) - 5)
                cap = torch.ldexp(torch.ones_like(z), re - 6) * 63
                decoded = ((z / grid).round() * grid).clamp(-cap, cap)
                score = (decoded - z).square().sum(dim=1) + trial.square() / 2048
                common = trial.gather(1, score.argmin(dim=1, keepdim=True))
                packed.extend((common, w - common))
                j += span
            if j < end:
                packed.append(rows[:, j + 1:end + 1])
        return {"coeff": torch.cat(packed, dim=1).reshape(-1, 128)}
    digits = torch.stack((coarse, rows - coarse), dim=2).reshape(-1, 2 * (k + 1), 128)
    packed = [digits[:, :2]]
    period = 2
    phase = int(k > 128)
    for j in range(k):
        if j % period == phase:
            packed.append(rows[:, j + 1:j + 2])
        else:
            packed.append(digits[:, 2 * j + 2:2 * j + 4])
    return {"coeff": torch.cat(packed, dim=1).reshape(-1, 128)}
