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
    r0 = aten.conv2d.default(_v(ins[0], [1, 16, 112, 112], [200704, 12544, 112, 1], 0), module.op0_weight, None, [2, 2], [1, 1], [1, 1], 16)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 16, 56, 56], [50176, 3136, 56, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op1, [1, 16, 56, 56], [50176, 3136, 56, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 16, 56, 56])}
# ---- end of the frozen reference ----

import numpy as np
import torch


def _rows(rows, bits):
    """Each row of 128 rounded to multiples of 2**(e - bits), e the exponent of the row's largest magnitude: values
    every NX8 format with that many mantissa bits holds exactly at the row's own scale."""
    out = np.zeros_like(rows)
    for r in range(rows.shape[0]):
        v = rows[r].astype(np.float64)
        top = float(np.max(np.abs(v)))
        if top == 0.0 or not np.isfinite(top):
            continue
        e = int(np.frexp(top)[1]) - 1
        step = 2.0 ** (e - bits)
        mag = np.minimum(np.floor(np.abs(v) / step + 0.5) * step, (2.0 - 2.0 ** -bits) * 2.0 ** e)
        out[r] = np.sign(v) * mag
    return out


def fold(module, **params):
    """20 rows of 128 lanes (channel c in lane c): tap-major (ky * 3 + kx), each a hi row then a lo row of the BN-folded
    depthwise weights, then the folded bias as a hi row and a lo row. lo = what hi left over (exact: the host rounds it to the run's format)."""
    w = module.op0_weight.to(torch.float64)
    co, _, kh, kw = w.shape
    scale = module.op1_weight.to(torch.float64) / torch.sqrt(module.op1_running_var.to(torch.float64) + 1e-5)
    wf = (w * scale.reshape(-1, 1, 1, 1)).reshape(co, kh * kw).t().numpy()
    b = (module.op1_bias.to(torch.float64) - module.op1_running_mean.to(torch.float64) * scale).numpy()
    vecs = np.zeros((kh * kw + 1, 128), dtype=np.float64)
    vecs[:kh * kw, :co] = wf
    vecs[kh * kw, :co] = b
    hi = _rows(vecs, 5)
    lo = vecs - hi
    out = np.zeros((2 * (kh * kw + 1), 128), dtype=np.float64)
    out[0::2] = hi
    out[1::2] = lo
    return {'weights': out}
