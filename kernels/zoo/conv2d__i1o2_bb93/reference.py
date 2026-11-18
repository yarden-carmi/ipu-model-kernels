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
    r0 = aten.conv2d.default(_v(ins[0], [1, 3, 224, 224], [150528, 50176, 224, 1], 0), module.op0_weight, module.op0_bias, [16, 16])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.cat.default([module.op1_cls_token, _v(op0, [1, 196, 768], [150528, 1, 196], 0)], 1)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 197, 768])}
# ---- end of the frozen reference ----


import torch

def fold(module, **params):
    w = module.op0_weight.to(torch.float64)
    co, ci, kh, kw = w.shape
    rows = torch.zeros(co // 128, 1 + kh * kw * ci, 128, dtype=torch.float64)
    rows[:, 1:] = w.reshape(co // 128, 128, ci, kh, kw).permute(0, 3, 4, 2, 1).reshape(co // 128, -1, 128)
    if params.get('bias'):
        b = module.op0_bias
        rows[:, 0] = b.reshape(-1, 128)
    return {'weights': rows, 'cls': module.op1_cls_token.reshape(-1, 128)}
