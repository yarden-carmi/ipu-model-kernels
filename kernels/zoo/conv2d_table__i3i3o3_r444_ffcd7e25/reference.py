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
    r0 = aten.conv2d.default(_v(ins[1], [1, 192, 32, 32], [196608, 1024, 32, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 96, 32, 32], [98304, 1024, 32, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 96, 32, 32], [98304, 1024, 32, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 96, 32, 32])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fold inference batch norm and split coefficients into NX8 hi/lo rows."""
    import numpy as np

    scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
    weight = module.op0_weight.double() * scale[:, None, None, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    cout, cin = weight.shape[:2]
    rows = np.concatenate((bias.numpy()[:, None], weight.numpy().reshape(cout, -1)), axis=1)
    parts = []
    for _ in range(3):
        exponent = np.frexp(np.abs(rows))[1] - 1
        step = np.exp2(exponent.astype(float) - 5)
        hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
        parts.append(hi)
        rows = rows - hi
    parts.append(rows)
    width, height = params["out0_d3"], params["out0_d2"]
    pack = min(height, 128 // width)
    if height % pack:
        pack = 1
    lane = np.arange(128)
    dx = np.tile(np.arange(-1, 2), cin * 3)
    x = lane[None, :] % width + dx[:, None]
    valid = (x >= 0) & (x < width) & (lane < width * pack)
    if pack == height:
        dy = np.tile(np.repeat(np.arange(-1, 2), 3), cin)
        y = lane[None, :] // width + dy[:, None]
        valid &= (y >= 0) & (y < height)
    mask = np.concatenate((np.ones((1, 128), dtype=bool), valid))
    expanded = np.stack(parts, axis=2)[..., None] * mask[None, :, None, :]
    return {"weights": np.concatenate((np.zeros((1, 128)), expanded.reshape(-1, 128)))}
