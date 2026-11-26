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
    r0 = aten.conv2d.default(_v(ins[0], [1, 32, 128, 128], [524288, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 128, 128, 128], [2097152, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 128, 128, 128], [2097152, 16384, 128, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 128, 128, 128])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack bias and transposed weights into output-channel tiles."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        if getattr(module, "op0_bias", None) is not None:
            bias = bias + module.op0_bias.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    padded = ((n + 127) // 128) * 128
    rows = weight.new_zeros((k + 1, padded))
    if bias is not None and params["bias"]:
        rows[0, :n] = bias
    rows[1:, :n] = weight.T
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1).reshape(-1, 128)
    # Quantize a coarse component and its residual separately to preserve small weights.
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 4)
    coarse = torch.round(rows / step) * step
    pairs = torch.stack((coarse, rows - coarse), dim=1)
    if n <= 64 and k <= 64 and k % 2 == 0:
        taps = rows[1:, :64].reshape(-1, 128)
        _, exp = torch.frexp(taps.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(exp, dtype=taps.dtype), exp - 4)
        high = torch.round(taps / step) * step
        return {"coeff": torch.cat((pairs[0], torch.stack((high, taps - high), dim=1).flatten(0, 1)))}
    if k % 16 == 0 and params["in0_d3"] % 8 == 0:
        if 16 < k <= 96:
            tiles = rows.reshape(-1, k + 1, 128)
            a, b = tiles[:, 1:].reshape(-1, k // 2, 2, 128).unbind(2)
            def quantum(w, scale):
                _, exp = torch.frexp(w.abs())
                return torch.maximum(torch.ldexp(torch.ones_like(w), exp - 6), scale / 128)
            peaks = torch.stack((a, b)).abs().amax(dim=-1, keepdim=True)
            _, exponent = torch.frexp(peaks)
            sa, sb = torch.ldexp(torch.ones_like(exponent, dtype=a.dtype), exponent - 1).unbind(0)
            step = torch.maximum(sa, sb) / 4096
            candidates = step.unsqueeze(-1) * torch.arange(-192, 193, dtype=a.dtype, device=a.device)
            def error(w, scale):
                v = w.unsqueeze(-1) - candidates
                q = quantum(v, scale.unsqueeze(-1))
                ceiling = scale.unsqueeze(-1) * (63 / 32)
                rounded = torch.minimum(torch.round(v.abs() / q) * q, ceiling).copysign(v)
                # Keep the binade of the largest coefficient stable, so the
                # scale used by the encoder matches the grid searched here.
                anchor = w.abs() == w.abs().amax(dim=-1, keepdim=True)
                invalid = (v.abs() >= 2 * scale.unsqueeze(-1)) | (anchor.unsqueeze(-1) & (v.abs() < scale.unsqueeze(-1)))
                return (rounded - v).masked_fill(invalid, float('inf'))
            loss = error(a, sa).square() + error(b, sb).square() + candidates.square() / 512
            correction = candidates.expand_as(loss).gather(-1, loss.argmin(-1, keepdim=True)).squeeze(-1)
            correction = correction.masked_fill((peaks == 0).any(dim=0), 0)
            compensated = torch.stack((a - correction, b - correction, correction), dim=2)
            tail = compensated.flatten(1, 2)
            return {"coeff": torch.cat((pairs.reshape(-1, k + 1, 2, 128)[:, 0], tail), dim=1).reshape(-1, 128)}
        split = 8 if k > 96 else 16
        single = torch.arange(k) % 16 >= split
        single = torch.cat((torch.tensor([False]), single)).repeat(padded // 128).to(rows.device)
        pairs[single, 0] = rows[single]
        keep = torch.stack((torch.ones_like(single), ~single), dim=1)
        return {"coeff": pairs[keep]}
    return {"coeff": pairs.reshape(-1, 128)}
