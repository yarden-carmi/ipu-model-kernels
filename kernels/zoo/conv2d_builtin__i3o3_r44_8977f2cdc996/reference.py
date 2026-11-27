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
    r0 = aten.conv2d.default(_v(ins[0], [1, 64, 64, 64], [262144, 4096, 64, 1], 0), module.weight, module.bias, [1, 1], [1, 1])
    op0 = _pick(r0, 0)  # step 0
    r0 = aten.relu.default(_v(op0, [1, 32, 64, 64], [131072, 4096, 64, 1], 0))
    op1 = _pick(r0, 0)  # step 0
    return {"out0": _out(op1, [1, 32, 64, 64])}
# ---- end of the frozen reference ----


def fold(module, **params):
    """Build scalar coefficient panels and masks for the packed spatial taps."""
    width, height = params['in0_d3'], params['in0_d2']
    pack = max(1, 128 // width)
    if height % pack:
        pack = 1
    chunks = (width + 127) // 128
    w = module.weight.detach().double()
    indices = []
    masks = [w.new_zeros(128)]
    lanes = torch.arange(128)
    for chunk in range(chunks):
        x = lanes % width if chunks == 1 else lanes + 128 * chunk
        active = lanes < pack * width if chunks == 1 else x < width
        for ky in (-1, 0, 1):
            for kx in (-1, 0, 1):
                horizontal = active & (x + kx >= 0) & (x + kx < width)
                if pack > 1:
                    local = (lanes // width + ky >= 0) & (lanes // width + ky < pack)
                else:
                    local = (lanes + kx >= 0) & (lanes + kx < 128)
                spill = (pack > 1 and ky != 0) or (chunks == 2 and kx != 0)
                keep = horizontal & local
                masks.append(keep.to(w.dtype))
                if chunk == 0:
                    indices.append(3 * (ky + 1) + kx + 1)
                if spill:
                    masks.append((horizontal & ~local).to(w.dtype))
                    if chunk == 0:
                        indices.append(indices[-1])
    taps = w.flatten(2)[:, :, indices].flatten(1)
    panels = torch.nn.functional.pad(taps, (0, -taps.shape[1] % 128))
    panels = panels.reshape(w.shape[0], -1, 128)
    bias = module.bias.double()[:, None, None].expand(-1, 1, 128)

    def split(rows):
        parts = []
        for _ in range(1):
            _, e = torch.frexp(rows.abs().amax(dim=-1, keepdim=True))
            step = torch.exp2(e.double() - 5)
            part = (rows / step).round().clamp(-32, 32) * step
            parts.append(part)
            rows = rows - part
        return torch.stack((*parts, rows), dim=2).flatten(1, 2)

    weights = torch.cat((split(bias), split(panels)), dim=1)
    return {'weights': weights.reshape(-1, 128), 'masks': torch.stack(masks)}
