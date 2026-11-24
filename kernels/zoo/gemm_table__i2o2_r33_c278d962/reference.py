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
    r0 = aten.view.default(_v(ins[0], [1, 256, 768], [196608, 768, 1], 0), [-1, 768])
    r1 = aten.addmm.default(module.bias, _l(r0, 0, [256, 768], [768, 1], 0), module.weight)
    r2 = aten.view.default(_l(r1, 0, [256, 3072], [3072, 1], 0), [1, 256, 3072])
    op0 = _pick(r2, 0)  # step 0
    r0 = aten.mul.Tensor(_v(op0, [1, 256, 3072], [786432, 3072, 1], 0), 0.5)
    r1 = aten.pow.Tensor_Scalar(_v(op0, [1, 256, 3072], [786432, 3072, 1], 0), 3.0)
    r2 = aten.mul.Tensor(_l(r1, 0, [1, 256, 3072], [786432, 3072, 1], 0), 0.044715)
    r3 = aten.add.Tensor(_v(op0, [1, 256, 3072], [786432, 3072, 1], 0), _l(r2, 0, [1, 256, 3072], [786432, 3072, 1], 0))
    r4 = aten.mul.Tensor(_l(r3, 0, [1, 256, 3072], [786432, 3072, 1], 0), 0.7978845608028654)
    r5 = aten.tanh.default(_l(r4, 0, [1, 256, 3072], [786432, 3072, 1], 0))
    r6 = aten.add.Tensor(_l(r5, 0, [1, 256, 3072], [786432, 3072, 1], 0), 1.0)
    r7 = aten.mul.Tensor(_l(r0, 0, [1, 256, 3072], [786432, 3072, 1], 0), _l(r6, 0, [1, 256, 3072], [786432, 3072, 1], 0))
    op1 = _pick(r7, 0)  # step 0
    return {"out0": _out(op1, [1, 256, 3072])}
# ---- end of the frozen reference ----


def fold(module, **params):
    n, k = params["n"], params["k"]
    weight = module.weight.detach()
    # The decomposed tanh GELU uses addmm's [k, n] right operand;
    # the exact GELU path uses linear's [n, k] weight.
    if params["act_out0"] == "gelu_tanh":
        weight = weight.reshape(k, n).transpose(0, 1)
    else:
        weight = weight.reshape(n, k)
    bias = module.bias.detach().reshape(n) if params["bias"] else weight.new_zeros(n)
    channels = torch.cat((bias[:, None], weight), dim=1)
    channels = torch.nn.functional.pad(channels, (0, 0, 0, (-n) % 128))
    return {"coeff": channels.reshape(-1, 128, k + 1).transpose(1, 2).reshape(-1, 128).contiguous()}
