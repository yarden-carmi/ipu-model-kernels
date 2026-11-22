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
    r0 = aten.linear.default(_v(ins[0], [1, 256, 384], [98304, 384, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 256, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Split weight chunks and broadcast bias into signed radix-16 planes."""
    weight = module.weight.detach().double()
    n, k = weight.shape

    def planes(rows):
        exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
        digits = torch.ldexp(rows.abs(), 16 - exp).round().long().clamp(max=65535)
        return torch.stack([
            torch.ldexp(((digits >> shift) & 15) * rows.sign(), exp + shift - 16)
            for shift in (12, 8, 4, 0)
        ], dim=-2).reshape(-1, 128).float()

    d3 = params["in0_d3"]
    pack = max(1, 128 // d3)
    if params["in0_d2"] % pack or (k // d3) % pack:
        pack = 1
    group = pack * d3
    groups = torch.nn.functional.pad(weight, (0, (-k) % group)).reshape(n, -1, group)
    folded = {"w": planes(torch.nn.functional.pad(groups, (0, (-group) % 128)).reshape(n, -1, 128))}
    if params["bias"]:
        folded["b"] = planes(module.bias.detach().double()[:, None].expand(-1, 128))
    return folded
