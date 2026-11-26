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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    r0 = aten.silu_.default(_v(op1, [1, 256, 64, 64], [1048576, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 0
    return {"out0": _out(op2, [1, 256, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack row-scaled digits and shared corrections per output channel."""
    n, k = params["n"], params["k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
        if getattr(module, "op0_bias", None) is not None:
            bias = bias + module.op0_bias.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    if bias is None or not params["bias"]:
        bias = weight.new_zeros(n)

    def split(rows, bits):
        _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
        step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - bits)
        coarse = torch.round(rows / step) * step
        return coarse, rows - coarse

    bits = 6 if k <= 16 else 5
    bias_digits = torch.stack(split(bias[:, None].expand(n, 128), bits), dim=1)

    def blocks(values, width):
        count = (values.shape[1] + width - 1) // width
        padded = torch.nn.functional.pad(values, (0, count * width - values.shape[1]))
        return torch.nn.functional.pad(padded.reshape(n, count, width), (0, 128 - width))

    if k >= 144:
        digits = torch.stack(split(blocks(weight, 8), 6), dim=2).reshape(n, -1, 128)
        packed = torch.cat((bias_digits, digits), dim=1)
    else:
        compensated = k <= 96
        quad = 8 <= k <= 16 and k % 4 == 0
        chunks = ([3, 3, 3, 3, 2, 2] if k == 16 else [4] * (k // 4)) if quad else None
        if quad:
            groups = len(chunks)
        elif k <= 16:
            groups = k // 2
        elif 32 < k <= 64:
            groups = k // 4
        elif compensated:
            groups = min(26, k // 2, k * 7 // 16)
        else:
            groups = min(k * 5 // 16, (k - 1) // 2)
        paired = 0 if quad else k - 2 * groups
        rows = blocks(weight[:, :paired], 32)
        if k <= 64 and paired:
            rows[:, 0, 127] = bias
        packed = torch.stack(split(rows, bits), dim=2).reshape(n, -1, 128)
        if k > 64 or quad:
            packed = torch.cat((bias_digits, packed), dim=1)
        if groups and not compensated:
            tail = weight.new_zeros(n, groups, 128)
            tail[..., 0] = weight[:, paired::2]
            tail[..., 127] = weight[:, paired + 1::2]
            packed = torch.cat((packed, tail), dim=1)
        elif groups:
            # w*x = (w-c)*x + c*sum(x) over each group. Pick a shared c
            # that reduces the rounding error of the row-scaled residuals.
            if quad:
                pair = torch.stack([torch.nn.functional.pad(p, (0, max(chunks) - size))
                                    for p, size in zip(weight.split(chunks, dim=1), chunks)], dim=1)
            else:
                pair = weight[:, paired:].reshape(n, groups, 2)
            peak = pair.abs().amax(dim=(1, 2), keepdim=True)
            if not paired and not quad:
                peak = torch.maximum(peak, bias_digits[:, :1, :1].abs())
            _, exponent = torch.frexp(peak)
            scale = torch.ldexp(torch.ones_like(peak), exponent - 1)
            s = scale.squeeze(-1).unsqueeze(-1)
            grid = torch.arange(-64, 65, dtype=weight.dtype, device=weight.device)
            candidates = s * grid / (4096 if k <= 16 else 1024)

            def error(tap):
                v = (tap.unsqueeze(-1) - candidates).abs()
                _, e = torch.frexp(v)
                quantum = torch.maximum(torch.ldexp(torch.ones_like(v), e - 1 - bits),
                                        s / (64 if k <= 16 else 256))
                rounded = torch.minimum(torch.round(v / quantum) * quantum, s * (2 - 2.0 ** -bits))
                return rounded - v + (v >= 2 * s) * s

            loss = sum(error(tap).square() for tap in pair.unbind(-1)) + candidates.square() / 4096
            correction = candidates.expand_as(loss).gather(-1, loss.argmin(dim=-1, keepdim=True)).squeeze(-1)
            tail = weight.new_zeros(n, 2, 128)
            residual = pair - correction[..., None]
            if quad:
                tail[:, 0, :k] = torch.cat([residual[:, j, :size] for j, size in enumerate(chunks)], dim=1)
            else:
                tail[:, 0, :groups] = residual[..., 0]
                tail[:, 0, 64:64 + groups] = residual[..., 1]
            tail[:, 0, 126] = scale.flatten()
            tail[:, 1, :groups] = correction
            if not paired and not quad:
                tail[:, :, 127] = bias_digits[:, :, 0]
            packed = torch.cat((packed, tail), dim=1)
    return {"coeff": torch.nn.functional.pad(packed.reshape(-1, 128), (0, 0, 0, 1))}
