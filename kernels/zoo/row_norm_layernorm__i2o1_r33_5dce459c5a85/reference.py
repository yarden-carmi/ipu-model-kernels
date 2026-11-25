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
    r0 = aten.layer_norm.default(_v(ins[0], [1, 257, 384], [98688, 384, 1], 0), [384], module.weight, module.bias, 1e-06)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 257, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    c = params["channels"]

    def split(x, pieces=2):
        x = x.reshape(-1, 128)
        parts = []
        for _ in range(pieces - 1):
            peak = x.abs().amax(dim=1, keepdim=True).clamp_min(1e-30)
            step = torch.exp2(torch.floor(torch.log2(peak)) - 6)
            hi = torch.round(x / step) * step
            parts.append(hi)
            x = x - hi
        return torch.stack((*parts, x), dim=1).reshape(-1, 128)

    def padded(x):
        return torch.nn.functional.pad(x.reshape(-1), (0, (-c) % 128))

    eps = params["eps"] * c
    scalars = torch.tensor([1 / c, eps], dtype=torch.float32)[:, None].repeat(1, 128)
    return {
        "gamma": split(padded(module.weight) * (0.5 * c**0.5), 3),
        "beta": split(padded(module.bias), 3),
        "scalars": torch.cat((split(scalars), torch.tensor([[3.0], [0.5]]).repeat(1, 128))),
    }
