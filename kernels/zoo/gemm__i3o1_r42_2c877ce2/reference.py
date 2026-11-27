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


# the replacement's recorded code (§4.6), the operation of op0
import torch

_STEP_PARAMS = {'bias': False, 'k': 48, 'm': 256, 'n': 768}

def forward(module, *inputs):
    """Step 2 of 3 of the replacement (gemm): the matrix product."""
    p = _STEP_PARAMS
    b, m, k, n = (int(p.get(x, 1)) for x in ("b", "m", "k", "n"))
    a = inputs[0].to(torch.float64).reshape(b, m, k)
    if len(inputs) > 1:
        c = inputs[1].to(torch.float64)
        c = c.reshape(b, n, k).transpose(-1, -2) if "gemm" == "bmm_nt" else c.reshape(b, k, n)
    else:
        c = getattr(module, "weight", getattr(module, "table", None))
        if c is None:
            raise ValueError("gemm needs a second operand and none is given")
        c = c.to(torch.float64)
        c = c if tuple(c.shape) == (k, n) else c.t() if tuple(c.shape) == (n, k) else c.reshape(k, n)
        c = c.expand(b, k, n)
    y = a @ c
    if "gemm" == "bmm_nt" and p.get("scale") not in (None, ""):
        y = y * float(p["scale"])
    if p.get("bias") and getattr(module, "bias", None) is not None:
        y = y + module.bias.to(torch.float64)
    return y.to(torch.float32)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [256, 768])}
# ---- end of the frozen reference ----


def fold(module, **params):
    k, n = int(params["k"]), int(params["n"])
    weight = module.weight.detach().reshape(k, n).t()
    bias = module.bias.detach().reshape(n) if params["bias"] else weight.new_zeros(n)
    data = torch.cat((bias[:, None], weight), dim=1)
    rows = torch.nn.functional.pad(data, (0, 0, 0, (-n) % 128))
    rows = rows.reshape(-1, 128, k + 1).transpose(1, 2)
    exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))[1]
    digits = torch.ldexp(rows.abs().double(), 12 - exp).round().long().clamp(max=4095)
    planes = [torch.ldexp(((digits >> shift) & 63) * rows.sign(), exp + shift - 12)
              for shift in (6, 0)]
    packed = torch.stack(planes, dim=2).reshape(-1, 128).float()
    return {"w": torch.nn.functional.pad(packed, (0, 0, 0, 1))}
