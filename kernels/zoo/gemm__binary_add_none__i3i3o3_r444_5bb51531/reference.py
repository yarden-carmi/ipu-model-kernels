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
    r0 = aten.conv2d.default(_v(ins[0], [1, 256, 64, 64], [1048576, 4096, 64, 1], 0), module.op0_weight)
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.batch_norm.default(_v(op0, [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.op1_weight, module.op1_bias, module.op1_running_mean, module.op1_running_var, False, 0.1, 1e-05, True)
    op1 = _pick(r0, 0)  # step 0
    op1 = r_(op1, "s0")  # stored
    r0 = aten.add.Tensor(_v(op1, [1, 64, 64, 64], [262144, 4096, 64, 1], 0), _v(ins[1], [1, 64, 64, 64], [262144, 4096, 64, 1], 0))
    op2 = _pick(r0, 0)  # step 1
    return {"out0": _out(op2, [1, 64, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Pack spatial GEMM coefficients in small blocks with sparse corrections."""
    n, k = params["s0_n"], params["s0_k"]
    if hasattr(module, "op1_running_var"):
        scale = module.op1_weight.double() * torch.rsqrt(module.op1_running_var.double() + 1e-5)
        weight = module.op0_weight.double().reshape(n, k) * scale[:, None]
        bias = module.op1_bias.double() - module.op1_running_mean.double() * scale
    else:
        weight = module.weight.double().reshape(n, k)
        bias = getattr(module, "bias", None)
    coeff = weight.new_zeros((n, 2, 128))
    if params["s0_bias"] and bias is not None:
        bias = bias.double()
        quantum = torch.ldexp(torch.ones_like(bias), torch.frexp(bias.abs())[1] - 5)
        hi = torch.round(bias / quantum) * quantum
        coeff[:, 0, :] = hi[:, None]
        coeff[:, 1, :] = (bias - hi)[:, None]
    rows = [coeff]
    if k % 64 == 0:
        original = weight.reshape(n, k // 16, 16)
        radius = original.abs().amax(-1, keepdim=True)
        step = torch.ldexp(torch.ones_like(radius), torch.frexp(radius)[1] - 11)
        lattice = torch.arange(-511, 512, device=weight.device)

        def quantize(values):
            mx = torch.frexp(values.abs().amax(-1, keepdim=True))[1]
            exp = torch.frexp(values.abs())[1]
            grid = torch.ldexp(torch.ones_like(values), torch.maximum(exp, mx - 2) - 6)
            nearest = torch.floor(values.abs() / grid + 0.5) * grid
            return values.sign() * torch.minimum(nearest, torch.ldexp(torch.full_like(mx, 63 / 64, dtype=values.dtype), mx))

        # A translation lets each block choose a better coefficient grid.
        # The corresponding sum of input rows removes it from the dot product.
        candidates = (step * lattice)[..., None]
        trial = torch.cat((original[..., None, :] + candidates, candidates), dim=-1)
        rounded = quantize(trial)
        hi = torch.cat((rounded[..., :1], trial[..., 1:]), -1)
        error = quantize(hi)[..., :16] - quantize(hi)[..., 16:] - original[..., None, :]
        error[..., 0] += trial[..., 0] - hi[..., 0]
        drift = error.sum(-1)
        score = error.square().sum(-1) + 0.04 * drift.square() + 0.08 * candidates[..., 0].square()
        choice = score.argmin(-1)
        selected = drift.gather(-1, choice[..., None]).squeeze(-1)
        total = selected.sum(1, keepdim=True)
        for _ in range(5):
            for block in range(k // 16):
                others = total - selected[:, block, None]
                cost = score[:, block] + 0.06 * (others + drift[:, block]).square()
                pick = cost.argmin(-1, keepdim=True)
                choice[:, block] = pick[:, 0]
                chosen_drift = drift[:, block].gather(-1, pick)
                selected[:, block] = chosen_drift[:, 0]
                total = others + chosen_drift
        idx = choice[..., None, None].expand(-1, -1, 1, 17)
        lo = (trial[..., :1] - hi[..., :1]).gather(-2, idx[..., :1]).squeeze(-1).squeeze(-1)
        hi = hi.gather(-2, idx).squeeze(-2)
        pad = torch.nn.functional.pad
        lo = torch.cat((coeff[:, 1, :1], lo), dim=-1)
        return {"w": torch.cat((coeff[:, :1], pad(lo[:, None], (0, 128 - lo.shape[-1])),
                                pad(hi, (0, 111))), 1).reshape(-1, 128)}
    def pack(piece):
        row = torch.nn.functional.pad(piece[:, None, :], (0, 128 - piece.shape[-1]))
        return row

    # Translate the coefficients by a representable scalar. The kernel
    # subtracts the corresponding scaled input sum from the dot product.
    radius = weight.abs().amax(1, keepdim=True)
    quantum = torch.ldexp(torch.ones_like(radius), torch.frexp(0.75 * radius)[1] - 6)
    steps = torch.arange(-63, 64, dtype=weight.dtype, device=weight.device)
    candidates = quantum * steps
    shifted = weight.clone()
    shifts = []
    def split_quad(j):
        return j % 4 == 0 or j % 16 == 1

    planes = list(range(0, min(k, 4), 2))
    for sweep, p in enumerate(planes * (3 if k % 64 == 0 else 1)):
        if k % 64 == 0:
            blocks = shifted.reshape(n, k // 4, 4)
            candidates4 = blocks[:, None, :, :].expand(-1, candidates.shape[1], -1, -1).clone()
            previous = shifts[p // 2] if sweep >= len(planes) else 0
            candidates4[:, :, :, p] += (candidates - previous)[:, :, None]
            mx = torch.frexp(candidates4.abs().amax(-1, keepdim=True))[1]
            pair_exp = torch.frexp(candidates4.reshape(n, candidates.shape[1], k // 4, 2, 2)
                                   .abs().amax(-1, keepdim=True))[1].repeat_interleave(2, -1).flatten(-2)
            pair_rows = torch.tensor([split_quad(j) for j in range(k // 4)], device=weight.device)
            mx = torch.where(pair_rows[None, None, :, None], pair_exp, mx)
            ex = torch.frexp(candidates4.abs())[1]
            grid = torch.ldexp(torch.ones_like(candidates4), torch.maximum(ex, mx - 2) - 6)
            rounded = candidates4.sign() * torch.minimum(torch.floor(candidates4.abs() / grid + 0.5) * grid,
                                                         torch.ldexp(torch.full_like(candidates4, 63 / 64), mx))
            error = (rounded - candidates4).reshape(n, candidates.shape[1], k // 4, 4).clone()
            error[:, :, :, 3] = 0
            error[:, :, ::4, 1] = 0
            error[:, :, 1::16, 1] = 0
            error = error.reshape(n, candidates.shape[1], -1)
            best = (error.square().sum(-1) + error.sum(-1).square() * 0.10).argmin(-1, keepdim=True)
            shift = candidates.gather(1, best)
            shifted[:, p::4] += shift - previous
            if sweep < len(planes):
                shifts.append(shift)
            else:
                shifts[p // 2] = shift
            continue
        even = weight[:, None, p::4] + candidates[:, :, None]
        odd = weight[:, None, p + 1::4]
        odd = torch.nn.functional.pad(odd, (0, even.shape[-1] - odd.shape[-1]))
        pair_grid = torch.ldexp(torch.ones_like(even), torch.frexp(torch.maximum(even.abs(), odd.abs()))[1] - 5)
        odd_hi = torch.round(odd / pair_grid) * pair_grid
        exp = torch.frexp(even.abs())[1]
        mx = torch.frexp(torch.maximum(even.abs(), odd_hi.abs()))[1]
        grid = torch.ldexp(torch.ones_like(even), torch.maximum(exp, mx - 2) - 6)
        rounded = even.sign() * torch.minimum(torch.floor(even.abs() / grid + 0.5) * grid,
                                              torch.ldexp(torch.full_like(even, 63 / 64), mx))
        error = rounded - even
        best = (error.square().sum(-1) + error.sum(-1).square() * 0.06).argmin(-1, keepdim=True)
        shift = candidates.gather(1, best)
        shifted[:, p::4] += shift
        shifts.append(shift)
    weight = shifted
    pieces = []
    for bi, block in enumerate(weight.split(2, dim=1)):
        for piece in (block,):
            extra = bi % 2 == 0 and split_quad(bi // 2)
            split = [1] if piece.shape[1] == 2 and (k % 64 != 0 or bi % 2 == 1 or extra) else []
            group = weight[:, (bi // 2) * 4:(bi // 2) * 4 + 4] if k % 64 == 0 and not split_quad(bi // 2) else piece
            group_exp = torch.frexp(group.abs().amax(-1, keepdim=True))[1]
            grid = torch.ldexp(torch.ones_like(piece[:, :1]), group_exp - 5)
            hi = piece.clone()
            hi[:, split] = torch.round(piece[:, split] / grid) * grid
            ex = torch.frexp(hi.abs())[1]
            mx = group_exp
            grid = torch.ldexp(torch.ones_like(hi), torch.maximum(ex, mx - 2) - 6)
            rounded = hi.sign() * torch.minimum(torch.floor(hi.abs() / grid + 0.5) * grid,
                                                torch.ldexp(torch.full_like(hi, 63 / 64), mx))
            keep = torch.zeros_like(hi, dtype=torch.bool)
            keep[:, split] = True
            error = (rounded - hi).masked_fill(keep, 0).sum(-1, keepdim=True)
            margin = (grid * 0.45).masked_fill(~keep | (hi == 0) | (ex == mx) |
                                             (hi.abs() == torch.ldexp(torch.ones_like(hi), ex - 1)), 0)
            pieces.append((piece, split, hi, margin, error))
    ratio = (sum(p[4] for p in pieces) / sum(p[3].sum(-1, keepdim=True) for p in pieces).clamp_min(1e-30)).clamp(-1, 1)
    lo = []
    extra_lo = []
    primary = []
    for bi, (piece, split, hi, margin, _) in enumerate(pieces):
        hi = hi + ratio * margin
        residual = (piece - hi)[:, split]
        if k % 64 == 0 and bi % 2 == 0 and split_quad(bi // 2):
            extra_lo.append(residual)
        else:
            lo.append(residual)
        primary.append(hi if k % 64 == 0 else pack(hi))
    if extra_lo:
        lo.extend(extra_lo)
    if k % 64 == 0:
        primary = [pack(row) for i in range(0, len(primary), 2)
                   for row in (primary[i:i+2] if split_quad(i // 2) else [torch.cat(primary[i:i+2], dim=-1)])]
    rows.extend([pack(torch.cat(lo, dim=-1)), *primary, pack(torch.cat(shifts, dim=1))])
    return {"w": torch.cat(rows, dim=1).reshape(-1, 128)}
