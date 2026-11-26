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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 128, 128], [1048576, 16384, 128, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 32, 128, 128], [524288, 16384, 128, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 32, 128, 128])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse inference batch norm and lay out primary and correction rows."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)

    if not params["bias"] or bias is None:
        bias = weight.new_zeros(n)
    if params["in0_d3"] >= 32 and n <= 128:
        # Each output feature has two bias rows and two rows per K block.
        taps = torch.nn.functional.pad(weight, (0, (-k) % 128)).reshape(n, -1, 128)
        seed = torch.nn.functional.pad(bias.reshape(n, 1), (0, 127))[:, None, :]
        panel = torch.cat((seed, taps), dim=1)
        _, exponent = torch.frexp(panel.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(panel[..., :1]), exponent - 4)
        coarse = torch.round(panel / step) * step
        if k > 128 and k % 128 == 0:
            for j in (1, 3, 5, 9, 11, 13):
                coarse[:, 1:, j::16] = panel[:, 1:, j::16]
        return {"coeff": torch.stack((coarse, panel - coarse), dim=2).reshape(-1, 128)}
    rows = []
    for lo in range(0, n, 128):
        b = bias.reshape(n)[lo:lo + 128]
        tile = torch.cat((b[None], weight[lo:lo + 128].T))
        tile = torch.nn.functional.pad(tile, (0, 128 - b.numel()))
        _, exponent = torch.frexp(tile.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(tile[:, :1]), exponent - 4)
        coarse = torch.round(tile / step) * step
        dual = torch.ones(k + 1, dtype=torch.bool, device=tile.device)
        if k < 256:
            for j in range(8):
                dual[1 + j:1 + (k // 8) * 8:8] = False
        primary = torch.where(dual[:, None], coarse, tile)
        planes = torch.stack((primary, tile - coarse), dim=1)
        keep = torch.stack((torch.ones_like(dual), dual), dim=1)
        rows.append(planes[keep])
    rows.append(weight.new_zeros((1, 128)))
    return {"coeff": torch.cat(rows)}
