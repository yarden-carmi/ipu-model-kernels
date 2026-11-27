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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 16, 56, 56])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch normalization into the convolution parameters."""
    k, n = int(params["k"]), int(params["n"])
    scale = module.op1_weight.detach().reshape(n).double() * torch.rsqrt(
        module.op1_running_var.detach().reshape(n).double() + 1e-5)
    weight = module.op0_weight.detach().reshape(n, k).double() * scale[:, None]
    bias = module.op1_bias.detach().reshape(n).double() - module.op1_running_mean.detach().reshape(n).double() * scale
    h = int(params["out0_d2"])
    pack = min(4, 128 // h)
    groups = (n + pack - 1) // pack
    rows = torch.zeros((groups, 1 + k * h, 128), dtype=torch.float32)
    for g in range(groups):
        for c in range(pack):
            j = g * pack + c
            if j < n:
                rows[g, 0, c*h:(c+1)*h] = bias[j]
                for y in range(h):
                    rows[g, 1+y::h, c*h+y] = weight[j]
    return {"w": torch.nn.functional.pad(rows.reshape(-1, 128), (0, 0, 0, 1))}
