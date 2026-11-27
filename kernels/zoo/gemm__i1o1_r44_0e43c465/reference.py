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
    r0 = aten.conv2d.default(_v(ins[0], [1, 120, 14, 14], [23520, 196, 14, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 48, 14, 14], [9408, 196, 14, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 48, 14, 14])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold convolution and inference batch normalization."""
    k, n = int(params["k"]), int(params["n"])
    scale = module.op1_weight.detach() / torch.sqrt(module.op1_running_var.detach() + 1e-5)
    weight = module.op0_weight.detach().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.detach() - module.op1_running_mean.detach() * scale
    pack = 2 if 17 <= n <= 64 and (int(params['out0_d0']) * int(params['out0_d2']) * int(params['out0_d3'])) % 2 == 0 else 1
    rows = weight.new_zeros((1 + k * pack + 1, 128))
    for p in range(pack):
        rows[0, p*n:(p+1)*n] = bias
        rows[1+p:1+k*pack:pack, p*n:(p+1)*n] = weight.T
    rows = rows[:-1].double()
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(rows.abs(), 12 - exp).round().long().clamp(max=4095)
    planes = [torch.ldexp(((digits >> shift) & 15) * rows.sign(), exp + shift - 12) for shift in (8, 4, 0)]
    packed = torch.stack(planes, dim=1).reshape(-1, 128).float()
    return {"w": torch.nn.functional.pad(packed, (0, 0, 0, 1))}
    if not (int(params["m"]) == 257 and k == 384):
        weight = module.weight.detach().reshape(n, k)
        bias = module.bias.detach().reshape(n) if params["bias"] else weight.new_zeros(n)
        data = torch.cat((bias[:, None], weight), dim=1)
        rows = torch.nn.functional.pad(data, (0, 0, 0, (-n) % 128))
        rows = rows.reshape(-1, 128, k + 1).transpose(1, 2)
        return {"w": torch.nn.functional.pad(rows.reshape(-1, 128), (0, 0, 0, 1))}
    scale = module.op1_lambda1.detach().reshape(n).double()
    weight = module.op0_weight.detach().reshape(n, k).double() * scale[:, None]
    bias = (module.op0_bias.detach().reshape(n).double() * scale
            if params["bias"] else weight.new_zeros(n))
    data = torch.cat((bias[:, None], weight), dim=1)
    rows = torch.nn.functional.pad(data, (0, 0, 0, (-n) % 128))
    rows = rows.reshape(-1, 128, k + 1).transpose(1, 2)
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(rows.abs(), 12 - exp).round().long().clamp(max=4095)
    planes = [torch.ldexp(((digits >> shift) & 15) * rows.sign(), exp + shift - 12)
              for shift in (8, 4, 0)]
    packed = torch.stack(planes, dim=2).reshape(-1, 128).float()
    # The final MAC prefetches one row past the last weight tile.
    return {"w": torch.nn.functional.pad(packed, (0, 0, 0, 1))}
