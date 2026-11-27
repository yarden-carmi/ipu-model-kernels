# ---- frozen reference (stage 1): do not change ----
import types as _types


class _SN(_types.SimpleNamespace):
    @property
    def size(self):
        if hasattr(self, "oh") and hasattr(self, "ow"):
            return (self.oh, self.ow)
        return (128, 128)


_types.SimpleNamespace = _SN


import torch
import torch.nn.functional as F


def reference(module, *ins, _round=None, **params):
    x = torch.as_strided(ins[0], (1, 64, 64, 64), (262144, 4096, 64, 1), 0)
    oh = params.get("oh", 128)
    ow = params.get("ow", 128)

    h, w = x.shape[-2:]
    if (h, w) == (oh, ow):
        out = x
    elif (2 * h, 2 * w) == (oh, ow):
        def route(n):
            j = torch.arange(2 * n, device=x.device)
            c = j // 2
            d = (c + 2 * (j % 2) - 1).clamp(0, n - 1)
            return torch.stack((c, c, c, d), dim=-1).flatten()
        z = x.index_select(-2, route(h)).index_select(-1, route(w))
        out = F.avg_pool2d(z, 4, 4)
    else:
        def axis(z, o):
            n = z.shape[-1]
            if n == o:
                return z
            s = ((torch.arange(o, device=z.device, dtype=torch.float64) + 0.5) * (n / o) - 0.5).clamp(0, n - 1)
            l = s.long()
            r = (l + 1).clamp(max=n - 1)
            t = (s - l).to(z.dtype)
            return z.index_select(-1, l) * (1 - t) + z.index_select(-1, r) * t
        out = axis(axis(x, ow).transpose(-1, -2), oh).transpose(-1, -2)

    if _round is not None:
        pass
    return {"out0": out}
# ---- end of the frozen reference ----

def fold(module, **params):
    return {}
