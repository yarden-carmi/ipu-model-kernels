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
    r0 = aten.linear.default(_v(ins[0], [1, 256, 768], [196608, 768, 1], 0), module.op0_weight, module.op0_bias)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.mul.Tensor(_v(op0, [1, 256, 128], [32768, 128, 1], 0), 0.5)
    r1 = aten.pow.Tensor_Scalar(_v(op0, [1, 256, 128], [32768, 128, 1], 0), 3.0)
    r2 = aten.mul.Tensor(_l(r1, 0, [1, 256, 128], [32768, 128, 1], 0), 0.044715)
    r3 = aten.add.Tensor(_v(op0, [1, 256, 128], [32768, 128, 1], 0), _l(r2, 0, [1, 256, 128], [32768, 128, 1], 0))
    r4 = aten.mul.Tensor(_l(r3, 0, [1, 256, 128], [32768, 128, 1], 0), 0.7978845608028654)
    r5 = aten.tanh.default(_l(r4, 0, [1, 256, 128], [32768, 128, 1], 0))
    r6 = aten.add.Tensor(_l(r5, 0, [1, 256, 128], [32768, 128, 1], 0), 1.0)
    r7 = aten.mul.Tensor(_l(r0, 0, [1, 256, 128], [32768, 128, 1], 0), _l(r6, 0, [1, 256, 128], [32768, 128, 1], 0))
    op1 = _pick(r7, 0)  # step 0
    op1 = r_(op1, "s0")  # stored
    r0 = aten.layer_norm.default(_v(op1, [1, 256, 128], [32768, 128, 1], 0), [128], module.op2_weight, module.op2_bias, 1e-12)
    op2 = _pick(r0, 0)  # step 1
    return {"out0": _out(op2, [1, 256, 128])}
# ---- end of the frozen reference ----


def fold(module, **params):
    n, k = params['s0_n'], params['s0_k']
    w = module.op0_weight.detach().reshape(n, k)
    b = module.op0_bias.detach().reshape(n) if params['s0_bias'] else w.new_zeros(n)
    pad = (-n) % 128
    coeff = torch.nn.functional.pad(torch.cat((b[:, None], w), dim=1), (0, 0, 0, pad))
    coeff = coeff.reshape(-1, 128, k + 1).transpose(1, 2).reshape(-1, 128).contiguous()

    def split(rows):
        parts = []
        for _ in range(2):
            peak = rows.abs().amax(dim=-1, keepdim=True).clamp_min(1e-35)
            step = torch.exp2(torch.floor(torch.log2(peak)) - 3)
            part = torch.round(rows / step) * step
            parts.append(part)
            rows = rows - part
        return torch.stack([*parts, rows], dim=1)

    gamma, beta = [split(torch.nn.functional.pad(t.detach().reshape(n), (0, pad)).reshape(-1, 128))
                   for t in (module.op2_weight, module.op2_bias)]
    reciprocal = split(w.new_full((1, 128), 1 / params['s1_channels'])).reshape(3, 128)
    eps = w.new_full((1, 128), params['s1_eps'])
    affine = torch.cat((gamma, beta), dim=1).reshape(-1, 128)
    return {'coeff': coeff, 'norm': torch.cat((reciprocal, eps, affine))}
