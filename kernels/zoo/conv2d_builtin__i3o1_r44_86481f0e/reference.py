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
    import types
    ins = tuple(t.clone() for t in ins)  # an in-place operation below writes on its own copies
    module = types.SimpleNamespace(**{k: v.clone() if hasattr(v, 'clone') else v
                                      for k, v in vars(module).items()})
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 56, 56], [200704, 3136, 56, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu_.default(_v(op0, [1, 128, 56, 56], [401408, 3136, 56, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 128, 56, 56])}
# ---- end of the frozen reference ----


def _fast_weights(weight, bias):
        co, ci, _, _ = weight.shape
        padded_bias = weight.new_zeros((1, 128))
        padded_bias[0, :co] = bias
        rows = [padded_bias]
        for y in (-1, 0, 1):
            for x in (-1, 0, 1):
                taps = [(dy + 1, dx + 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                        if (not y or dy != y) and (not x or dx != x)]
                for i in range(0, len(taps), 2):
                    block = weight.new_zeros((co, 128))
                    for half, (dy, dx) in enumerate(taps[i:i + 2]):
                        block[:, 64 * half:64 * half + ci] = weight[:, :, dy, dx]
                    rows.append(block)
        rows.append(weight.new_zeros((1, 128)))
        return {"weights": torch.cat(rows)}

def fold(module, **params):
    if hasattr(module, "weight"):
        weight = module.weight.double()
        bias = module.bias.double() if params["bias"] else weight.new_zeros(weight.shape[0])
        cout, cin, kh, kw = weight.shape
        b = weight.new_zeros((1, 128))
        b[0, :cout] = bias
        w = weight.new_zeros((kh, kw, cin, 128))
        w[:, :, :, :cout] = weight.permute(2, 3, 1, 0)
        rows = torch.cat((b, w.reshape(-1, 128)))
        _, exp = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exp.double() - 6)
        high = (rows / step).round().clamp(-63, 63) * step
        return {"weights": torch.stack((high, rows - high), dim=1).reshape(-1, 128)}
    weight = module.op0_weight.double()
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    conv_bias = getattr(module, "op0_bias", None)
    if params["bias"] and conv_bias is not None:
        bias = bias + conv_bias.double() * scale
    weight = weight * scale[:, None, None, None]
    cout, cin, kh, kw = weight.shape
    groups = params["groups"]
    total_cin = params["cin"]
    depthwise = groups == total_cin == cout
    if not depthwise and groups != 1:
        expanded = weight.new_zeros((cout, total_cin, kh, kw))
        outputs = cout // groups
        for group in range(groups):
            expanded[group * outputs:(group + 1) * outputs, group * cin:(group + 1) * cin] = weight[group * outputs:(group + 1) * outputs]
        weight = expanded
        cin = total_cin
    blocks = (cout + 127) // 128
    padded = weight.new_zeros((blocks * 128, cin, kh, kw))
    padded[:cout] = weight
    b = weight.new_zeros(blocks * 128)
    b[:cout] = bias
    rows = []
    for block in range(blocks):
        rows.append(b[block * 128:(block + 1) * 128].reshape(1, 128))
        rows.append(padded[block * 128:(block + 1) * 128].permute(2, 3, 1, 0).reshape(-1, 128))
    rows = torch.cat(rows)
    def digit(values):
        _, exp = torch.frexp(values.abs().amax(dim=-1, keepdim=True))
        step = torch.exp2(exp.double() - 6)
        return (values / step).round().clamp(-63, 63) * step
    high = digit(rows)
    result = torch.stack((high, rows - high), dim=1).reshape(-1, 128)
    return {'weights': result}
