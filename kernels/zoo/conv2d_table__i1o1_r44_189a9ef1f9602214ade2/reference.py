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
    r0 = aten.conv2d.default(_v(ins[0], [1, 128, 16, 16], [32768, 256, 16, 1], 0), module.op0_weight, None, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 128, 16, 16], [32768, 256, 16, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 128, 16, 16], [32768, 256, 16, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 128, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Fuse BN and emit the leading and residual rows used by the kernel."""
    import numpy as np

    weight = module.op0_weight.double()
    channels = weight.shape[0]
    conv_bias = getattr(module, "op0_bias", None)
    bias = weight.new_zeros(channels) if conv_bias is None else conv_bias.double()
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() / (module.op1_running_var.double() + 1e-5).sqrt()
        bias = module.op1_bias.double() + (bias - module.op1_running_mean.double()) * scale
        weight = weight * scale[:, None, None, None]

    cin = params['cin']
    if params['groups'] == 1 and 2 <= cin <= 4 and channels <= 16 and weight.shape[2:] == (3, 3):
        packed = np.zeros((10, 128))
        packed[0, :channels] = bias.numpy()
        packed[1:, :16 * cin] = np.pad(
            weight.permute(2, 3, 1, 0).reshape(9, cin, channels).numpy(),
            ((0, 0), (0, 0), (0, 16 - channels)),
        ).reshape(9, 16 * cin)
        exponent = np.frexp(np.max(np.abs(packed), axis=-1, keepdims=True))[1] - 1
        step = np.exp2(exponent.astype(float) - 5)
        hi = np.sign(packed) * np.minimum(np.floor(np.abs(packed) / step + 0.5), 63) * step
        return {'weights': np.stack((hi, packed - hi), axis=1).reshape(-1, 128)}

    chunks = (channels + 127) // 128
    if params["groups"] == 1:
        # Each output chunk has its own tap-major, input-channel-minor matrix.
        rows = weight.permute(2, 3, 1, 0).reshape(-1, channels)
        rows = torch.cat((rows, bias[None]))
    else:
        if params["groups"] != params["cin"] or params["cin"] != channels:
            raise ValueError("expected dense or multiplier-one depthwise convolution")
        rows = torch.cat((bias[None], weight[:, 0].flatten(1).T))

    rows = np.pad(rows.numpy(), ((0, 0), (0, chunks * 128 - channels)))
    rows = rows.reshape(-1, chunks, 128).transpose(1, 0, 2)
    exponent = np.frexp(np.max(np.abs(rows), axis=-1, keepdims=True))[1] - 1
    step = np.exp2(exponent.astype(float) - 5)
    hi = np.sign(rows) * np.minimum(np.floor(np.abs(rows) / step + 0.5), 63) * step
    dense = params['groups'] == 1
    cin = params['cin']
    last_tap = weight.shape[2] * weight.shape[3] - 1
    edge_dense = (dense and channels < 128 and cin <= 128 and last_tap == 8
                  and params['padding'] == params['stride'] == 1
                  and min(params['out0_d2'], params['out0_d3']) > 1)
    direct_dw = (not dense and params['stride'] == params['padding'] == 1 and last_tap == 8
                 and min(params['in0_d2'], params['in0_d3']) > 2)
    single = (((0, 2, 6, 8) if params['stride'] == 2 else ()) if not dense else
              () if edge_dense else (0, 1, 2, 6, 7, 8))
    short_tap = (dense and channels == cin == 128 and weight.shape[2:] == (3, 3)
                 and params['padding'] == params['stride'] == 1
                 and min(params['out0_d2'], params['out0_d3']) > 1)
    # Use one row for selected perimeter taps, two for the rest and the bias.
    frames = np.concatenate([
        row for chunk, leading in zip(rows, hi)
        for i, (r, lead) in enumerate(zip(chunk, leading))
        for row in ([lead[None], (r-lead)[None]]
                       if not (short_tap and 4 * cin <= i < 4 * cin + 48) and (last_tap != 8 or (dense and cin <= 4)
                       or ((i // cin if dense else i - 1) not in single and not (direct_dw and i == 0))) else [r[None]])
    ], axis=0)
    return {"weights": frames}
