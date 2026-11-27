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
    r0 = aten.conv2d.default(_v(ins[0], [1, 3, 224, 224], [150528, 50176, 224, 1], 0), module.op0_weight, module.op0_bias, [14, 14])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.cat.default([module.op1_cls_token, _v(op0, [1, 256, 384], [98304, 1, 256], 0)], 1)
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 257, 384])}
# ---- end of the frozen reference ----


def fold(module, **params):
    weight = module.op0_weight
    cout = params['cout']
    weights = weight.reshape(cout, -1)
    weights = torch.nn.functional.pad(weights, (0, -weights.shape[1] % 128))
    tokens = params['out0_d1']
    patches = ((params['h'] - params['kh']) // params['stride'] + 1) * (
        (params['w'] - params['kw']) // params['stride'] + 1)
    prefix = int(tokens > patches)
    seed = weight.new_zeros(cout, (tokens + 127) // 128 * 128)
    if params['bias']:
        seed[:, prefix:prefix + patches] = module.op0_bias.reshape(cout, 1)
    if prefix:
        seed[:, 0] = module.op1_cls_token.reshape(cout)
    if tokens > patches + prefix:
        seed[:, prefix + patches:tokens] = module.op1_detection_tokens.reshape(-1, cout).T
    wo = (params['w'] - params['kw']) // params['stride'] + 1
    if (wo == 16 and 128 < params['in0_d3'] <= 256
            and 128 <= 15 * params['stride'] <= 256 - params['kw']
            and params['stride'] <= 16 and patches % 128 == 0
            and tokens == patches + 1):
        aux = torch.nn.functional.pad(weight.reshape(-1, params['kw']), (0, 128 - params['kw']))
    else:
        aux = weight.new_zeros(2, 128)
        aux[0, 127] = 1
    return {'weights': weights.reshape(-1, 128), 'seed': seed.reshape(-1, 128), 'aux': aux}
