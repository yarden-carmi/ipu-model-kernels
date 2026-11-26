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
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        if getattr(module, "op0_bias", None) is not None:
            bias = bias + module.op0_bias.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)

    if bias is None or not params["bias"]:
        bias = weight.new_zeros(n)
    rows = torch.cat((bias.double()[None], weight.T))
    rows = torch.nn.functional.pad(rows, (0, (-n) % 128)).reshape(k + 1, -1, 128).transpose(0, 1)
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 6)
    coarse = (rows / step).round().clamp(-63, 63) * step
    packed = [coarse[:, :1], rows[:, :1] - coarse[:, :1]]
    medium = k == 32 and n <= 128
    if medium:
        packed = [rows[:, :1]]
        _, elem_exp = torch.frexp(rows.abs())
        grid = torch.ldexp(torch.ones_like(rows), torch.maximum(elem_exp, exponent - 2) - 6)
        for j in range(1, k + 1, 4):
            w, g = rows[:, j+1:j+4], grid[:, j+1:j+4]
            # Choose one offset for the three taps on their row-scaled grids.
            # The kernel multiplies that offset by the sum of their inputs.
            step = g.amax(dim=1, keepdim=True)
            delta = torch.linspace(-0.75, 0.75, 97, dtype=w.dtype, device=w.device) * step[..., None]
            v = (w[..., None] - delta).abs()
            row_exp = exponent[:, j+1:j+4, :, None]
            _, ve = torch.frexp(v)
            quantum = torch.ldexp(torch.ones_like(v), torch.maximum(ve, row_exp - 2) - 6)
            top = torch.ldexp(torch.ones_like(row_exp, dtype=w.dtype), row_exp - 1)
            quantized = torch.minimum((v / quantum).round() * quantum, top * (2 - 1/32))
            err = (quantized - v).abs()
            loss = (err.square() / (w[..., None].abs() + 8 * g[..., None])).sum(dim=1, keepdim=True)
            loss = loss + (v >= 2 * top).any(dim=1, keepdim=True) * step[..., None]
            shared = delta.gather(-1, loss.argmin(dim=-1, keepdim=True)).squeeze(-1)
            packed.extend((coarse[:, j:j+1], rows[:, j:j+1] - coarse[:, j:j+1], shared, w - shared))
        return {"coeff": torch.cat(packed, dim=1).reshape(-1, 128)}
    if 16 < k < 128 and k % 32 == 0 and not medium:
        # One shared residual replaces two separate residual products.
        _, elem_exp = torch.frexp(rows.abs())
        grid = torch.ldexp(torch.ones_like(rows), torch.maximum(elem_exp, exponent - 2) - 6)
        for j in range(1, k + 1, 2):
            w = rows[:, j:j+2]
            g = grid[:, j:j+2]
            r = w - (w / g).round() * g
            anchor = torch.where(g[:, :1] >= g[:, 1:], r[:, :1], r[:, 1:])
            q = ((w - anchor) / g).round() * g
            shared = (w - q).mean(dim=1, keepdim=True)
            packed.extend((shared, w - shared))
        return {"coeff": torch.cat(packed, dim=1).reshape(-1, 128)}
    short = k <= 16 and n <= 128 and k % 8 == 0
    if short:
        packed = [rows[:, :1]]
    for j in range(k):
        i = j + 1
        single = (j % 2 == 0 if short
                  else j % 4 != 3 if k >= 128 or k <= 16 else j % 2 == 0)
        if single:
            packed.append(rows[:, i:i+1])
        else:
            packed.extend((coarse[:, i:i+1], rows[:, i:i+1] - coarse[:, i:i+1]))
    return {"coeff": torch.cat(packed, dim=1).reshape(-1, 128)}
