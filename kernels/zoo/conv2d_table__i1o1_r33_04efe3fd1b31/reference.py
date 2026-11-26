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
    r0 = aten.conv1d.default(_v(ins[0], [1, 80, 3000], [240000, 3000, 1], 0), module.weight, module.bias, [1], [1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.gelu.default(_v(op0, [1, 512, 3000], [1536000, 3000, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 512, 3000])}
# ---- end of the frozen reference ----


def fold(module, **params):
    import numpy as np
    w = module.weight.double()
    cout, ni, kw = w.shape
    cin, groups = params['cin'], params['groups']
    bias = getattr(module, 'bias', None)
    bias = w.new_zeros(cout) if bias is None else bias.double()
    if groups == cin == cout:
        taps = w[:, 0].T
    else:
        if groups != 1:
            expanded = w.new_zeros(cout, cin, kw)
            no = cout // groups
            for g in range(groups):
                expanded[g*no:(g+1)*no, g*ni:(g+1)*ni] = w[g*no:(g+1)*no]
            w = expanded
        stride = params['stride']
        if kw == 3 and params['padding'] == 1 and params['out0_d2'] % (6 - 2 * stride) == 0:
            a, b, c = w.double().permute(2, 1, 0)
            taps = torch.cat((a + c, a, b, -c, b))
        else:
            taps = w.permute(2, 1, 0).reshape(-1, cout)
    chunks = (cout + 127) // 128
    rows = torch.cat((bias[None], taps)).numpy()
    rows = np.pad(rows, ((0, 0), (0, chunks*128 - cout)))
    rows = rows.reshape(-1, chunks, 128).transpose(1, 0, 2)
    step = np.exp2(np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 6.)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    return {'weights': np.stack((hi, rows - hi), axis=-2).reshape(-1, 128)}
