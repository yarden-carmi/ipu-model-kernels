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


# the replacement's recorded code (§4.6), the operation of op0
def fn(x, numel):
    return x.to(torch.float16).to(torch.float32)

import torch

_STEP_PARAMS = {'numel': 12288}
_STEP_NUMEL = 12288

def forward(module, *inputs):
    """Step 1 of 3 of the replacement (round_fp16): its primitive's recorded reference, as the chain check calls it."""
    import inspect
    named = {**vars(module), **_STEP_PARAMS}
    ps = inspect.signature(fn).parameters
    if any(p.kind == p.VAR_KEYWORD for p in ps.values()):
        kw = dict(named)
    else:
        kw = {x: v for x, v in named.items() if x in ps and ps[x].kind != ps[x].POSITIONAL_ONLY}
    slots = [p for p in ps.values() if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD) and p.name not in kw]

    def f(*ins_):
        pos, by_name, rest = [], dict(kw), list(ins_)
        for p in slots:
            if not rest:
                break
            if p.kind == p.POSITIONAL_ONLY:
                pos.append(rest.pop(0))
            else:
                by_name[p.name] = rest.pop(0)
        return fn(*pos, *rest, **by_name)
    # whole, else per item of the leading dimensions, as the chain check calls it (pathcheck._call): when the whole
    # call raises or gives other than the step's output size
    whole, err = None, None
    try:
        whole = f(*inputs)
        if _STEP_NUMEL is None or whole.numel() == _STEP_NUMEL:
            return whole
    except Exception as e:
        err = e
    lead = inputs[0].shape[:-2] if inputs and inputs[0].dim() > 2 else ()
    if lead and all(a.dim() > 2 and a.shape[:-2] == lead for a in inputs):
        flat = [a.reshape(-1, *a.shape[-2:]) for a in inputs]
        try:
            outs = [f(*[a[i] for a in flat]) for i in range(flat[0].shape[0])]
            items = torch.stack(outs).reshape(*lead, *outs[0].shape[-2:])
            if whole is None or items.numel() == _STEP_NUMEL:
                return items
            return whole
        except Exception:
            if err is not None:
                raise err from None
            raise
    if whole is not None:
        return whole
    raise err


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = forward(module, _v(ins[0], [1, 48, 16, 16], [12288, 256, 16, 1], 0))  # the replacement (step 0)
    return {"out0": _out(op0, [1, 48, 16, 16])}
# ---- end of the frozen reference ----

def fold(module, **params):
    return {}
