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
    """Fold batch norm and share a correction between adjacent taps."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op0_weight"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        if getattr(module, "op0_bias", None) is not None:
            bias = bias + module.op0_bias.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    rows = weight.new_zeros((k + 1, ((n + 127) // 128) * 128))
    if bias is not None and params["bias"]:
        rows[0, :n] = bias
    rows[1:, :n] = weight.T
    if n <= 64 and k <= 16:
        w = rows[:, :64]
        _, exp = torch.frexp(w.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(exp, dtype=w.dtype), exp - 5)
        coarse = (w / step).round() * step
        packed = torch.cat((coarse, (w - coarse) * 32), dim=1)
        scale = w.new_zeros((1, 128))
        scale[0, 0] = 1 / 32
        return {"coeff": torch.cat((packed, scale))}
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    _, row_exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    grid = torch.ldexp(torch.ones_like(row_exp, dtype=rows.dtype), row_exp - 6)
    coarse = (rows[:, :1] / grid[:, :1]).round().clamp(-63, 63) * grid[:, :1]
    tiles = [coarse, rows[:, :1] - coarse]
    _, elem_exp = torch.frexp(rows.abs())
    grid = torch.ldexp(torch.ones_like(rows), torch.maximum(elem_exp - 1, row_exp - 3) - 5)
    j = 0
    while j < k:
        i = j + 1
        local = j % 16
        size = 3 if 32 < k < 128 else 2
        if local % size == 0 and local + size <= (16 if size == 3 else 12) and j + size <= k:
            w, g = rows[:, i:i+size], grid[:, i:i+size]
            r = w - (w / g).round() * g
            anchor = r.gather(1, g.argmax(dim=1, keepdim=True))
            q = ((w - anchor) / g).round() * g
            shared = (w - q).mean(dim=1, keepdim=True)
            if size == 3:
                # Search neighboring grid phases, including the original
                # phase, without changing the exact folded decomposition.
                trial = torch.cat([shared, r, shared + g, shared - g], dim=1)
                z = w.unsqueeze(2) - trial.unsqueeze(1)
                re = row_exp[:, i:i+size].unsqueeze(2)
                _, ze = torch.frexp(z.abs())
                step = torch.ldexp(torch.ones_like(z), torch.maximum(ze - 1, re - 3) - 5)
                cap = torch.ldexp(torch.ones_like(z), re - 6) * 63
                decoded = ((z / step).round() * step).clamp(-cap, cap)
                score = ((decoded - z).square()).sum(dim=1) + trial.square() / 2048
                shared = trial.gather(1, score.argmin(dim=1, keepdim=True))
            tiles.extend((shared, w - shared))
            j += size
        else:
            tiles.append(rows[:, i:i+1])
            j += 1
    return {"coeff": torch.nn.functional.pad(torch.cat(tiles, dim=1).reshape(-1, 128), (0, 0, 0, 1))}
