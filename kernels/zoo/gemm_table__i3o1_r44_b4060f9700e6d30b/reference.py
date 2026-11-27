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


def _digits(rows, bits):
    """Split row-scaled coefficients into a coarse term and a residual."""
    _, exponent = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - bits)
    coarse = torch.round(rows / step) * step
    return torch.stack((coarse, rows - coarse), dim=-2)


def old_fold(module, **params):
    n, k = params['n'], params['k']
    source = getattr(module, 'op0_weight', getattr(module, 'weight', None))
    weight = source.double().reshape(n, k)
    source_bias = getattr(module, 'op0_bias', getattr(module, 'bias', None))
    bias = weight.new_zeros(n) if source_bias is None else source_bias.double().reshape(n)
    if hasattr(module, 'op1_running_var'):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = weight * scale[:, None]
        bias = (bias - module.op1_running_mean.double()) * scale + module.op1_bias.double()
    if not params['bias']:
        bias = weight.new_zeros(n)

    if k <= 128:
        span = 4 if k == 64 else (3 if k <= 96 else 2)
        prefix = 0 if k <= 32 or k == 64 else (k // 16 if k > 96 else (k // 3 if k > 64 else k // 4))
        groups = (k - prefix + span - 1) // span
        sizes = [2] * 2 + [3] * 4 if k == 16 else ([3] * 6 + [2] * 7 if k == 32 else [span] * (groups - 1) + [k - prefix - span * (groups - 1)])
        bits = 6 if k <= 16 else 5
        main = weight.new_zeros(n, 128)
        fine = torch.zeros_like(main)
        bias_digits = _digits(bias[:, None], bits).reshape(n, 2)
        single = 8 <= k <= 16
        if not single:
            fine[:, 127] = bias_digits[:, 1]
        if prefix:
            digits = _digits(weight[:, :prefix], bits)
            main[:, :prefix] = digits[:, 0]
            fine[:, :prefix] = digits[:, 1]
        peak = torch.maximum(weight.abs().amax(1, keepdim=True), bias.new_zeros(n, 1))
        _, exp = torch.frexp(peak)
        scale = torch.ldexp(torch.ones_like(peak), exp - 1)
        original_grid = 32 < k <= 64
        if k < 128 and not original_grid:
            main[:, 127] = scale[:, 0]
        peak_fine = torch.maximum(fine.abs().amax(1, keepdim=True), scale / (64 if bits == 6 else 32))
        _, ef = torch.frexp(peak_fine)
        fine_scale = torch.ldexp(torch.ones_like(peak_fine), ef - 1)
        if not original_grid:
            fine[:, 126] = fine_scale[:, 0]
        grid = torch.arange(-256, 257, dtype=weight.dtype, device=weight.device)
        v = grid * fine_scale / 256
        _, ve = torch.frexp(v.abs())
        vstep = torch.maximum(torch.ldexp(torch.ones_like(v), ve - 1 - bits), fine_scale / (64 if bits == 6 else 256))
        candidates = (v / vstep).round() * vstep
        if original_grid:
            candidates = scale * torch.arange(-128, 129, dtype=weight.dtype, device=weight.device) / 4096
        start = prefix
        for g, count in enumerate(sizes):
            taps = weight[:, start:start + count]
            residual = taps.unsqueeze(-1) - candidates[:, None, :]
            mag = residual.abs()
            _, e = torch.frexp(mag)
            quantum = torch.maximum(torch.ldexp(torch.ones_like(mag), e - 1 - bits), scale[:, :, None] / (64 if bits == 6 else 256))
            rounded = torch.minimum((mag / quantum).round() * quantum, scale[:, :, None] * (2 - 2.**-bits))
            loss = (rounded - mag).square().sum(1) + candidates.square() / 4096
            common = candidates.gather(1, loss.argmin(dim=1, keepdim=True))
            main[:, start:start + taps.size(1)] = taps - common
            fine[:, prefix + g] = common[:, 0]
            start += count
        b = weight.new_zeros(n, 128)
        b[:, 127] = bias if single else bias_digits[:, 0]
        packed = torch.stack((b, main, fine) if single else (b, fine, main), dim=1)
    elif k <= 384:
        blocks = (k + 127) // 128
        rows = torch.nn.functional.pad(weight, (0, blocks * 128 - k)).reshape(n, blocks, 128)
        packed = torch.cat((_digits(bias[:, None].expand(n, 128), 5), rows), dim=1)
    elif k >= 144:
        width = 8
        blocks = (k + width - 1) // width
        rows = weight.new_zeros(n, blocks, 128)
        rows[:, :, :width] = torch.nn.functional.pad(weight, (0, blocks * width - k)).reshape(n, blocks, width)
        packed = torch.cat((_digits(bias[:, None].expand(n, 128), 5), rows), dim=1)
    else:
        compensated = k <= 96
        groups = k // 2 if k <= 16 else (min(26, k // 2, k * 7 // 16) if compensated else min(k * 5 // 16, (k - 1) // 2))
        if 32 < k <= 64:
            groups = k // 4
        quad = 8 <= k <= 16 and k % 4 == 0
        if quad:
            chunks = [3, 3, 3, 3, 2, 2] if k == 16 else [4] * (k // 4)
            groups = len(chunks)
        paired = 0 if quad else k - 2 * groups
        blocks = (paired + 31) // 32
        rows = weight.new_zeros(n, blocks, 128)
        rows[:, :, :32] = torch.nn.functional.pad(weight[:, :paired], (0, blocks * 32 - paired)).reshape(n, blocks, 32)
        if k <= 64 and paired:
            rows[:, 0, 127] = bias
        bits = 6 if k <= 16 else 5
        packed = _digits(rows, bits).reshape(n, -1, 128)
        if k > 64 or quad:
            packed = torch.cat((_digits(bias[:, None].expand(n, 128), bits), packed), dim=1)
        if paired < k:
            if compensated:
                if quad:
                    pieces = weight.split(chunks, dim=1)
                    pair = torch.stack([torch.nn.functional.pad(piece, (0, max(chunks) - size))
                                        for piece, size in zip(pieces, chunks)], dim=1)
                else:
                    pair = weight[:, paired:].reshape(n, groups, 2)
                peak = pair.abs().amax(dim=(1, 2), keepdim=True)
                if not paired and not quad:
                    digits = _digits(bias[:, None], bits).reshape(n, 2)
                    peak = torch.maximum(peak, digits[:, 0].abs().reshape(n, 1, 1))
                _, exponent = torch.frexp(peak)
                scale = torch.ldexp(torch.ones_like(peak), exponent - 1)
                s = scale.squeeze(-1)
                grid = torch.arange(-64, 65, dtype=weight.dtype, device=weight.device)
                candidates = s.unsqueeze(-1) * grid / (4096 if k <= 16 else 1024)
                mantissa = 6 if k <= 16 else 5

                def error(w):
                    v = (w.unsqueeze(-1) - candidates).abs()
                    _, e = torch.frexp(v)
                    quantum = torch.maximum(torch.ldexp(torch.ones_like(v), e - 1 - mantissa),
                                            s.unsqueeze(-1) / (64 if k <= 16 else 256))
                    rounded = torch.minimum(torch.round(v / quantum) * quantum,
                                            (s * (2 - 2.0 ** -mantissa)).unsqueeze(-1))
                    return rounded - v + (v >= 2 * s.unsqueeze(-1)) * s.unsqueeze(-1)

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
                    tail[:, :, 127] = digits
            else:
                tail = weight.new_zeros(n, groups, 128)
                tail[..., 0] = weight[:, paired::2]
                tail[..., 127] = weight[:, paired + 1::2]
            packed = torch.cat((packed, tail), dim=1)
    return {'coeff': torch.nn.functional.pad(packed.reshape(-1, 128), (0, 0, 0, 1))}

def fold(module, **params):
    n, k = params['n'], params['k']
    scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
    weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
    bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    if getattr(module, 'op0_bias', None) is not None:
        bias = bias + module.op0_bias.double() * scale
    padded = ((n + 127) // 128) * 128
    rows = weight.new_zeros((k + 1, padded))
    if params['bias']:
        rows[0, :n] = bias
    rows[1:, :n] = weight.T
    rows = rows.reshape(k + 1, -1, 128).transpose(0, 1).reshape(-1, 128)
    _, exponent = torch.frexp(rows.abs().amax(dim=1, keepdim=True))
    step = torch.ldexp(torch.ones_like(exponent, dtype=rows.dtype), exponent - 4)
    coarse = torch.round(rows / step) * step
    pairs = torch.stack((coarse, rows - coarse), dim=1)
    width, height = params['in0_d3'], params['in0_d2']
    limit = min(height, 128 // width)
    pixels = width * (1 if height % limit else limit)
    if k >= 32 and k % 16 == 0 and pixels % 8 == 0:
        index = torch.arange(rows.shape[0], device=rows.device) % (k + 1)
        single = (index > 0) & ((index - 1) % 16 >= 16)
        pairs[single, 0] = rows[single]
        return {'coeff': pairs[torch.stack((torch.ones_like(single), ~single), dim=1)]}
    return {'coeff': pairs.reshape(-1, 128)}
