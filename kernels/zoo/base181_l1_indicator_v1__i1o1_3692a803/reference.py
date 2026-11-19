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


# the replacement's recorded code (§4.6), the operation of op0
def fn(x, **params):
    import torch
    tokens, vocab = int(params['tokens']), int(params['vocab'])
    a = x.reshape(tokens, 1).to(torch.int64)
    j = torch.arange(vocab, device=x.device, dtype=torch.int64).reshape(1, vocab)
    distance = torch.zeros((tokens, vocab), device=x.device, dtype=torch.int64)
    p = 1
    while p < vocab or p == 1:
        distance = distance + ((a // p) % 181 - (j // p) % 181).abs()
        p *= 181
    return (1 - distance).clamp_min(0).to(torch.float32)

_STEP_PARAMS = {'tokens': 256, 'vocab': 30522}

def forward(module, *inputs):
    """Step 1 of 2 of the replacement (base181_l1_indicator_v1): its primitive's recorded reference, as the chain check calls it."""
    import inspect
    named = {**vars(module), **_STEP_PARAMS}
    ps = inspect.signature(fn).parameters
    if any(p.kind == p.VAR_KEYWORD for p in ps.values()):
        kw = dict(named)
    else:
        kw = {x: v for x, v in named.items() if x in ps and ps[x].kind != ps[x].POSITIONAL_ONLY}
    slots = [p for p in ps.values() if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD) and p.name not in kw]
    pos, rest = [], list(inputs)
    for p in slots:
        if not rest:
            break
        if p.kind == p.POSITIONAL_ONLY:
            pos.append(rest.pop(0))
        else:
            kw[p.name] = rest.pop(0)
    return fn(*pos, *rest, **kw)


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 256], [256, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [256, 30522])}
# ---- end of the frozen reference ----

def fold(module, **params):
    v = int(params['vocab'])
    j = torch.arange(((v + 127) // 128) * 128)
    return {'digits': torch.cat([
        torch.stack([((j // (32 ** k)) % 32) * (32 ** k) * 1024
                     for k in range(3)]).reshape(-1, 128),
        torch.full((1, 128), 6),
        torch.full((1, 128), 1024),
        torch.full((1, 128), 5),
    ]).float()}
