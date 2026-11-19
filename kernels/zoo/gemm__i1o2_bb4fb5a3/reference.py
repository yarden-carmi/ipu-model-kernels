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


# the replacement's recorded code (§4.6), the operation of op0
import torch

_STEP_PARAMS = {'bias': False, 'k': 30522, 'm': 64, 'n': 384}

def forward(module, *inputs):
    """Step 2 of 2 of the replacement (gemm): the matrix product."""
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
    op0 = forward(module, _v(ins[0], [64, 30522], [30522, 1], 0))  # the replacement (step 0)
    r0 = aten.add.Tensor(_v(op0, [1, 64, 384], [24576, 384, 1], 0), module.op1_const0)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.add.Tensor(_v(op1, [1, 64, 384], [24576, 384, 1], 0), module.op2_const0)
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 64, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    n, k, m = (int(params[x]) for x in ('n', 'k', 'm'))
    source = getattr(module, 'weight', getattr(module, 'table', None)).detach()
    if tuple(source.shape) != (k, n):
        source = source.t() if tuple(source.shape) == (n, k) else source.reshape(k, n)
    kp, np = ((k + 127) // 128) * 128, ((n + 127) // 128) * 128
    w = source.new_zeros((kp, np))
    w[:k, :n] = source
    a = source.new_zeros((m, np))
    a[:, :n] = module.op1_const0.detach().reshape(m, n)
    a2 = source.new_zeros((m, np))
    a2[:, :n] = module.op2_const0.detach().reshape(m, n)
    result = {'w': w.reshape(-1, 128).contiguous(), 'addend': torch.cat((a.reshape(-1, 128), a2.reshape(-1, 128)))}
    if params['bias']:
        b = source.new_zeros(np)
        b[:n] = module.bias.detach()
        result['b'] = b
    return result
