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
    r0 = aten.linear.default(_v(ins[0], [1, 257, 384], [98688, 384, 1], 0), module.weight, module.bias)
    op0 = _pick(r0, 0)  # step 0
    return {"out0": _out(op0, [1, 257, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Encode weight chunks and broadcast bias as signed radix-32 planes."""
    scaled = hasattr(module, "op1_lambda1")
    weight = (module.op0_weight if scaled else module.weight).detach().double()
    n, k = weight.shape
    if scaled:
        scale = module.op1_lambda1.detach().reshape(n).double()
        weight = weight * scale[:, None]

    def planes(rows):
        exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
        digits = torch.ldexp(rows.abs(), 25 - exp).round().long().clamp(max=(1 << 25) - 1)
        return torch.stack([
            torch.ldexp(((digits >> shift) & 31) * rows.sign(), exp + shift - 25)
            for shift in (20, 15, 10, 5, 0)
        ], dim=-2).reshape(-1, 128).float()

    bias = weight.new_zeros(n)
    if params["bias"]:
        bias = (module.op0_bias if scaled else module.bias).detach().double()
        if scaled:
            bias = bias * scale
    rows = torch.cat((bias[:, None], weight), dim=1)
    rows = torch.nn.functional.pad(rows, (0, 0, 0, (-n) % 128))
    return {"w": planes(rows.reshape(-1, 128, k + 1).transpose(1, 2))}
