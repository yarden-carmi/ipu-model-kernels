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
    """Fold inference batch norm, then split each row into coarse and residual."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op0_weight"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    if bias is None or not params["bias"]:
        bias = weight.new_zeros(n)

    spatial = (params["m"] != params["in0_d0"] * params["in0_d1"]
               or k != params["in0_d2"] or n != params["out0_d2"])
    if spatial:
        blocks = (n + 127) // 128
        rows = weight.new_zeros((blocks, k + 1, 128))
        for b in range(blocks):
            lo, hi = b * 128, min(n, (b + 1) * 128)
            rows[b, 0, :hi - lo] = bias[lo:hi]
            rows[b, 1:, :hi - lo] = weight[lo:hi].T
    else:
        chunks = (k + 127) // 128
        rows = weight.new_zeros((n, chunks + 1, 128))
        rows[:, 0, 0] = bias
        rows[:, 1:, :].reshape(n, -1)[:, :k] = weight

    rows = rows.reshape(-1, 128)
    _, exp = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exp, dtype=rows.dtype), exp - 4)
    coarse = torch.round(rows / step) * step
    pairs = torch.stack((coarse, rows - coarse), dim=1)
    if spatial:
        # Keep the bias split and encode the last tap of each group directly.
        period = 6 if 32 < k <= 64 else (5 if 64 < k < 128 else 4)
        single = torch.arange(k + 1, device=rows.device) % period == 0
        single[0] = False
        single = single.repeat(blocks)
        pairs[single, 0] = rows[single]
        keep = torch.stack((torch.ones_like(single), ~single), dim=1)
        return {"coeff": pairs[keep]}
    return {"coeff": pairs.reshape(-1, 128)}
