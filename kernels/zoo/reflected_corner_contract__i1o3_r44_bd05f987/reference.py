from __future__ import annotations

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
def forward(module, *inputs):
    import torch
    x=inputs[0]
    c,h,w=x.shape
    oh,ow=module.size
    if (h,w)==(oh,ow): return x
    def axis(n,m,dyadic):
        j=torch.arange(m,device=x.device)
        if dyadic:
            a=j//2
            return a,(a+2*(j%2)-1).clamp(0,n-1),None
        d=2*m
        p=((2*j+1)*n-m).clamp(0,(n-1)*d)
        a=p//d
        return a,(a+1).clamp(max=n-1),(p%d).to(x.dtype)/d
    dyadic=(oh,ow)==(2*h,2*w)
    a,b,t=axis(h,oh,dyadic)
    l,r,u=axis(w,ow,dyadic)
    v=torch.stack([x[:,i[:,None],j[None,:]] for i,j in ((a,l),(a,r),(b,l),(b,r))],dim=-1)
    if dyadic: return (v.reshape(-1,4) @ x.new_tensor([[9],[3],[3],[1]]).div(16)).reshape(c,oh,ow)
    t,u=t[:,None],u[None,:]
    k=torch.stack([(1-t)*(1-u),(1-t)*u,t*(1-u),t*u],dim=-1)
    return torch.bmm(v.reshape(c,-1,4).transpose(0,1),k.reshape(-1,4,1)).squeeze(-1).transpose(0,1).reshape(c,oh,ow)


# how the model run calls it (§4.6, pathcheck.call_candidate)
import math
import types

CALL = '__call__'
BINARY = ('add', 'sub', 'mul', 'div', 'max', 'min')


def _upsample_size(call: Any) -> tuple[int, int] | None:
    """An upsample's output (h, w) from its ATen call: its `output_size`, else its input's size times its scale
    factors (rounded down, as ATen does)."""
    import torch
    if not isinstance(call, (list, tuple)) or not call or not isinstance(call[0], torch.Tensor) or call[0].dim() < 2:
        return None
    if len(call) > 1 and isinstance(call[1], (list, tuple)) and len(call[1]) == 2:
        return int(call[1][0]), int(call[1][1])
    h, w = call[0].shape[-2:]
    for v in call[2:]:
        if isinstance(v, (list, tuple)) and len(v) == 2 and all(isinstance(x, (int, float)) for x in v):
            return int(math.floor(h * v[0])), int(math.floor(w * v[1]))
    return None


def call_candidate(forward: Any, op: str, inputs: list[Any], consts: dict[str, Any], call: Any = None) -> Any:
    """`forward(module, *inputs)` as §4.6 calls it (``call(forward, *a)`` makes the call): an upsample's code once
    per image of a batch (``[channels, h, w]``, its output size as `module.size`), stacked; an embedding's ids as
    `[tokens]`; an elementwise operation's number operand among the inputs, as a 0-d tensor (v3.29)."""
    import types

    import torch
    call = call or (lambda f, *a: f(*a))
    consts = dict(consts)
    args = consts.pop(CALL, None)
    inputs = list(inputs)
    # the model run gives the code the check's shapes (§4.6, v3.29)
    if op == "embedding" and inputs:
        inputs[0] = inputs[0].reshape(-1)                       # the ids as `[tokens]`, whatever the batch shape
    if op in BINARY and isinstance(args, (list, tuple)) and len(inputs) == 1 and len(args) >= 2:
        two = list(args[:2])                                    # a number operand, in its place, as a 0-d tensor
        if sum(isinstance(a, torch.Tensor) for a in two) == 1 and \
                all(isinstance(a, torch.Tensor) or (isinstance(a, (int, float)) and not isinstance(a, bool))
                    for a in two):
            x = inputs[0]
            inputs = [x if isinstance(a, torch.Tensor) else
                      torch.tensor(a, dtype=torch.float32 if x.is_floating_point() or isinstance(a, float)
                                   else x.dtype, device=x.device) for a in two]
    if op == "upsample" and "size" not in consts:
        size = _upsample_size(args)
        if size is not None:
            consts["size"] = size
    module = types.SimpleNamespace(**consts)
    if op == "upsample" and inputs and inputs[0].dim() == 4:
        return torch.stack([call(forward, module, x, *inputs[1:]) for x in inputs[0]])
    return call(forward, module, *inputs)


def _cand(forward, kind, module, inputs, args):
    """The replacement's code called as the model run calls it (§4.6)."""
    return call_candidate(forward, kind, list(inputs), {**vars(module), CALL: args})


def reference(module, *ins, _round=None, **params):
    aten = torch.ops.aten
    r_ = _round or (lambda t, where: t)
    op0 = _cand(forward, 'upsample', module, [_v(ins[0], [1, 64, 8, 8], [4096, 64, 8, 1], 0)], [_v(ins[0], [1, 64, 8, 8], [4096, 64, 8, 1], 0), [16, 16], True, None])  # the replacement (step 0)
    return {"out0": _out(op0, [1, 64, 16, 16])}
# ---- end of the frozen reference ----


def fold(module, **params):
    return {}
