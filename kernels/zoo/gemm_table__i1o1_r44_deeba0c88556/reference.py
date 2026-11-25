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
    """Fold batch norm and tile the bias and weights across output lanes."""
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
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1)
    if params["m"] == 1:
        return {"coeff": rows.reshape(-1, 128)}

    # Preserve more coefficient precision with a residual for the bias
    # and a periodic subset of reduction weights.
    _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exp, dtype=rows.dtype), exp - 6)
    coarse = torch.round(rows / step).clamp(-63, 63) * step
    taps = torch.arange(k + 1, device=rows.device) - 1
    split = (taps < 0) | (taps % 16 >= (7 if k > 32 else 2 if n < 128 else 0))
    if 32 < k < 128 and k % 32 == 0 and n > 128 and n % 128 == 0 and params["m"] % 2 == 0:
        # A common offset s in two adjacent weights contributes s * (x0 + x1).
        # Anchor it to the coarser coefficient grid, then center the rounding
        # errors of the two adjusted weights. The decomposition is exact in FP32
        # up to arithmetic rounding; the grid only guides the choice of offset.
        tiles = [coarse[:, :1], (rows - coarse)[:, :1]]
        scale_exp = exp - 1
        _, elem_exp = torch.frexp(rows.abs())
        grid = torch.ldexp(torch.ones_like(rows), torch.maximum(elem_exp - 1, scale_exp - 2) - 5)
        for start in range(1, k + 1, 32):
            tiles.extend((coarse[:, start:start + 4], rows[:, start:start + 4] - coarse[:, start:start + 4]))
            tiles[-2:] = [torch.stack(tiles[-2:], dim=2).flatten(1, 2)]
            for j in range(start + 4, start + 32, 2):
                w = rows[:, j:j + 2]
                g = grid[:, j:j + 2]
                r = w - (w / g).round() * g
                anchor = torch.where(g[:, :1] >= g[:, 1:], r[:, :1], r[:, 1:])
                q = ((w - anchor) / g).round() * g
                shared = (w - q).mean(dim=1, keepdim=True)
                tiles.extend((shared, w - shared))
        return {"coeff": torch.cat(tiles, dim=1).reshape(-1, 128)}
    first = torch.where(split[None, :, None], coarse, rows)
    interleaved = torch.stack((first, rows - coarse), dim=2).flatten(1, 2)
    keep = torch.stack((torch.ones_like(split), split), dim=1).flatten()
    return {"coeff": interleaved[:, keep].reshape(-1, 128)}
