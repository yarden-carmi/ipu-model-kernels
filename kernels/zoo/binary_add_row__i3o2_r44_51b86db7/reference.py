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
    r0 = aten.add.Tensor(_v(ins[0], [1, 8, 64, 64], [32768, 4096, 64, 1], 0), module.op0_const0)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 8, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Lay out the repeating constant in output row and lane order."""
    height, width = params["in0_d2"], params["in0_d3"]
    tile = height * width
    inner = params["inner"]
    tiles = params["out0_d0"] * params["out0_d1"]
    if tile % inner == 0:
        tiles = 1
    elif inner % tile == 0:
        tiles = min(tiles, inner // tile)
    operand = module.op0_const0.reshape(-1)
    indices = torch.arange(tiles * tile) % operand.numel()
    values = operand[indices].reshape(tiles, height, width).transpose(1, 2)
    return {"operand": torch.nn.functional.pad(values.reshape(-1, height), (0, 128 - height))}
