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
    """Arrange one coefficient vector per input channel, shared by packed pixels."""
    k, n = int(params["k"]), int(params["n"])
    if hasattr(module, "op0_weight"):
        scale = module.op1_weight.detach().reshape(n) / torch.sqrt(module.op1_running_var.detach().reshape(n) + 1e-5)
        weight = module.op0_weight.detach().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.detach().reshape(n) - module.op1_running_mean.detach().reshape(n) * scale
    else:
        weight = module.weight.detach().reshape(n, k)
        bias = module.bias.detach().reshape(n) if params["bias"] else weight.new_zeros(n)
    pack = 2 if 16 < n <= 64 and int(params["out0_d0"]) * int(params["out0_d2"]) * int(params["out0_d3"]) % 2 == 0 else 1
    tiles = (n * pack + 127) // 128
    rows = []
    for tile in range(tiles):
        b = bias.new_zeros(128)
        for lane in range(128):
            idx = tile * 128 + lane
            if idx < n * pack:
                b[lane] = bias[idx % n]
        rows.append(b)
        for j in range(k):
            row = bias.new_zeros(128)
            width = min(128, n - tile * 128)
            row[:width] = weight[tile * 128:tile * 128 + width, j]
            rows.append(row)
    data = torch.stack(rows).double()
    exp = torch.frexp(data.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(data.abs(), 12 - exp).round().long().clamp(max=4095)
    planes = [torch.ldexp(((digits >> shift) & 15) * data.sign(), exp + shift - 12)
              for shift in (8, 4, 0)]
    packed = torch.stack(planes, dim=1).reshape(-1, 128).float()
    return {"w": torch.nn.functional.pad(packed, (0, 0, 0, 1))}
