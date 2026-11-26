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
    r0 = aten.matmul.default(_v(ins[0], [1, 8, 64, 64], [32768, 64, 512, 1], 0), _v(ins[1], [1, 8, 64, 64], [32768, 64, 1, 512], 0))
    op0 = _pick(r0, 0)  # step 0
    op0 = r_(op0, "s0")  # stored
    r0 = aten.mul.Tensor(_v(op0, [1, 8, 64, 64], [32768, 4096, 64, 1], 0), 0.125)
    op1 = _pick(r0, 0)  # step 1
    op1 = r_(op1, "s1")  # stored
    r0 = aten.add.Tensor(_v(op1, [1, 8, 64, 64], [32768, 4096, 64, 1], 0), module.op2_const0)
    op2 = _pick(r0, 0)  # step 2
    op2 = r_(op2, "s2")  # stored
    r0 = aten.softmax.int(_v(op2, [1, 8, 64, 64], [32768, 4096, 64, 1], 0), -1, torch.float32)
    op3 = _pick(r0, 0)  # step 3
    return {"out0": _out(op3, [1, 8, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    width = params["s3_n"]
    bias = module.op2_const0.reshape(-1, width)
    coeff = bias.new_tensor([1.4375, 1.4426950408889634 - 1.4375, 0.125])
    return {"operand": torch.cat((coeff[:, None].expand(-1, 128),
                                  torch.nn.functional.pad(bias, (0, 128 - width))))}
