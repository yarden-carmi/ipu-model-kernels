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
    r0 = aten.layer_norm.default(_v(ins[0], [1, 1829, 384], [702336, 384, 1], 0), [384], module.weight, module.bias, 1e-12)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 1829, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    def split(tensor):
        residual = tensor.float().flatten()
        parts = []
        for _ in range(7):
            step = torch.exp2(torch.floor(torch.log2(residual.abs().clamp_min(1e-30))) - 1)
            part = torch.round(residual / step) * step
            parts.append(part)
            residual = residual - part
        return torch.stack([*parts, residual], dim=1)

    def broadcast(tensor):
        return tensor.reshape(-1, 1).expand(-1, 128).contiguous()

    affine = torch.cat([split(module.weight), split(module.bias)], dim=1)
    stats = split(torch.tensor([1.0 / params['channels'], params['eps']]))
    stats = torch.cat([stats.flatten(), torch.tensor([1.5, 0.5])])
    return {'affine': broadcast(affine), 'stats': broadcast(stats)}
