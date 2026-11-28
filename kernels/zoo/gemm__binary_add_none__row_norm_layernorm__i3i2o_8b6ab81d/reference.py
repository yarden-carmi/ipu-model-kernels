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
    r0 = aten.linear.default(_v(ins[0], [1, 256, 384], [98304, 384, 1], 0), module.op0_weight, module.op0_bias)
    op0 = _pick(r0, 0)  # step 0
    op0 = r_(op0, "s0")  # stored
    r0 = aten.add.Tensor(_v(op0, [1, 256, 384], [98304, 384, 1], 0), _v(ins[1], [1, 256, 384], [98304, 384, 1], 0))
    op1 = _pick(r0, 0)  # step 1
    op1 = r_(op1, "s1")  # stored
    r0 = aten.layer_norm.default(_v(op1, [1, 256, 384], [98304, 384, 1], 0), [384], module.op2_weight, module.op2_bias, 1e-12)
    op2 = _pick(r0, 0)  # step 2
    return {"out0": _out(op2, [1, 256, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    k, n = params['s0_k'], params['s0_n']
    tiles = (n + 127) // 128
    pad = 128 * tiles - n

    def split(rows):
        rows = rows.double()
        exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
        high = torch.ldexp(torch.ldexp(rows, 4 - exp).round(), exp - 4)
        return torch.stack((high, rows - high), dim=1).float()

    bias = module.op0_bias if params['s0_bias'] else module.op0_weight.new_zeros(n)
    w = torch.cat((bias.reshape(n, 1), module.op0_weight.reshape(n, k)), dim=1)
    w = torch.nn.functional.pad(w, (0, 0, 0, pad))
    affine = torch.stack((module.op2_weight.reshape(n), module.op2_bias.reshape(n)))
    affine = torch.nn.functional.pad(affine, (0, pad)).reshape(2, tiles, 128)
    affine = split(affine.transpose(0, 1).reshape(-1, 128))
    return {
        'w': w.reshape(tiles, 128, k + 1).transpose(1, 2).reshape(-1, 128).contiguous(),
        'affine': affine.reshape(-1, 128),
        'crow': torch.cat((split(torch.full((1, 128), 1 / n)).reshape(2, 128),
                           torch.full((1, 128), params['s2_eps']),
                           torch.full((1, 128), 0.5), torch.full((1, 128), 1.5))),
    }
