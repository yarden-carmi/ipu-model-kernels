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
    r0 = aten.conv2d.default(_v(ins[0], [1, 3, 512, 864], [1327104, 442368, 864, 1], 0), module.op0_weight, module.op0_bias, [16, 16])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.cat.default([module.op1_cls_token, _v(op0, [1, 1728, 384], [663552, 1, 1728], 0), module.op1_detection_tokens], 1)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 1829, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    cout = weight.shape[0]
    weights = weight.reshape(cout, -1)
    weights = torch.nn.functional.pad(weights, (0, -weights.shape[1] % 128))
    patches = ((params['h'] - params['kh']) // params['stride'] + 1) * (
        (params['w'] - params['kw']) // params['stride'] + 1)
    tokens = params['out0_d1'] - patches
    bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    seed = weight.new_zeros(cout, (params['out0_d1'] + 127) // 128 * 128)
    prefix = int(tokens > 0)
    if bias is not None and params['bias']:
        seed[:, prefix:prefix + patches] = bias[:, None]
    if prefix:
        seed[:, :1] = module.op1_cls_token.reshape(1, cout).T
        seed[:, prefix + patches:prefix + patches + tokens - 1] = (
            module.op1_detection_tokens.reshape(tokens - 1, cout).T)
    mask = weight.new_zeros(2, 128)
    mask[0, 127] = 1
    return {'weights': weights, 'seed': seed, 'mask': mask}
