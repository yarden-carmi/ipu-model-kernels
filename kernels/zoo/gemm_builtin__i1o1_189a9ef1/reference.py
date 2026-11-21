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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 72, 56, 56], [225792, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 72, 56, 56], [225792, 3136, 56, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 72, 56, 56])}
# ---- end of the frozen reference ----


import numpy as np
import torch


def _e1_rows(rows, fe=2, fm=5):
    """Each row of 128 rounded to the signed NX8 grid (fe exponent bits, fm mantissa bits) at its own row scale, as the host writes a constant row."""
    out = np.zeros_like(rows)
    emax = (1 << fe) - 1
    for r in range(rows.shape[0]):
        v = rows[r].astype(np.float32).astype(np.float64)
        top = float(np.max(np.abs(v)))
        if top == 0.0 or not np.isfinite(top):
            continue
        e = int(np.frexp(np.float32(top))[1]) - 1
        low = e - (emax - 1)
        mag = np.abs(v)
        lev = np.where(mag >= 2.0 ** low, np.floor(np.log2(np.maximum(mag, 1e-300))), low)
        step = 2.0 ** (lev - fm)
        q = np.floor(mag / step + 0.5) * step
        q = np.minimum(q, (2.0 - 2.0 ** -fm) * 2.0 ** e)
        out[r] = np.sign(v) * q
    return out


def fold(module, **params):
    """Rows of 128 lanes (output channel in lane): bias hi, bias lo, then for each input channel its hi row and lo row
    (BN folded in; lo = the e2 rounding of what hi left over), and one zero row that the streaming reads last."""
    n, k = int(params["n"]), int(params["k"])
    w = module.op0_weight.to(torch.float64).reshape(n, k)
    scale = module.op1_weight.to(torch.float64) / torch.sqrt(module.op1_running_var.to(torch.float64) + 1e-5)
    b = module.op1_bias.to(torch.float64) - module.op1_running_mean.to(torch.float64) * scale
    wf = (w * scale.reshape(-1, 1)).numpy()
    vec = np.zeros((k + 1, 128), dtype=np.float64)
    vec[0, :n] = b.numpy()
    vec[1:, :n] = wf.T
    hi = _e1_rows(vec)
    lo = _e1_rows(vec - hi)
    out = np.zeros((2 * k + 3, 128), dtype=np.float64)
    out[0], out[1] = hi[0], lo[0]
    out[2:2 * k + 2:2] = hi[1:]
    out[3:2 * k + 2:2] = lo[1:]
    return {"w": out}
