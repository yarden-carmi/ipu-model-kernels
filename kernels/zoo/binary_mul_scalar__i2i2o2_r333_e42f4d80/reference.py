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
    r0 = aten.div.Tensor(_v(ins[0], [2, 512, 2], [1024, 2, 1], 0), module.op0_const0)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.cat.default([_v(op0, [2, 512, 2], [1024, 2, 1], 0), _v(ins[1], [2, 512, 1], [512, 1, 1], 0)], 2)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [2, 512, 3])}
# ---- end of the frozen reference ----


def fold(module, **params):
    # The reference computes in0 / op0_const0, so the kernel multiplies by its
    # reciprocal, held in R_CYCLIC as three constant rows made from the call's
    # parameters: 1/c on every lane (full chunks), 1/c on lanes 0..q-1 only (the
    # tail's in0 part, q = in0_d2 % 128, so in0's padding never reaches lane q),
    # and 1 at lane q only (MULT.RC.VE with src = Ra[128] = R1[0] = in1[g]).
    c = float(module.op0_const0.reshape(-1)[0])
    r = 1.0 / c
    q = int(params["in0_d2"]) % 128
    constfull = torch.full((1, 128), r)
    consttail = torch.zeros((1, 128))
    consttail[0, :q] = r
    onehot = torch.zeros((1, 128))
    onehot[0, q] = 1.0
    return {"constfull": constfull, "consttail": consttail, "onehot": onehot}
