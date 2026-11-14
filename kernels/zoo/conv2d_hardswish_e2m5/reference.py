import torch
import torch.nn.functional as F


def reference(**kw):
    cin, cout, groups = int(kw["cin"]), int(kw["cout"]), int(kw["groups"])
    h, w = int(kw["h"]), int(kw["w"])
    kh, kwd = int(kw["kh"]), int(kw["kw"])
    stride, pad = int(kw["stride"]), int(kw["padding"])
    nbi = -(-cin // 128)
    nbo = -(-cout // 128)
    cing = cin // groups

    # in0: one row per (y, x, 128-channel block); channels on lanes.
    x = kw["in0"].to(torch.float64).reshape(h, w, nbi * 128)[:, :, :cin]
    x = x.permute(2, 0, 1)[None]
    # weights: folded rows ((tap * cing + ic) * nbo + block), lanes = output channel.
    wf = kw["weights"].to(torch.float64).reshape(kh, kwd, cing, nbo * 128)[..., :cout]
    wt = wf.permute(3, 2, 0, 1).contiguous()  # (cout, cing, kh, kw)
    b = kw["bias_vec"].to(torch.float64).reshape(nbo * 128)[:cout]

    y = F.conv2d(x, wt, b, stride=stride, padding=pad, groups=groups)
    y = F.hardswish(y)[0].permute(1, 2, 0)  # (ho, wo, cout)
    ho, wo = y.shape[0], y.shape[1]
    out = torch.zeros(ho, wo, nbo * 128, dtype=torch.float64)
    out[..., :cout] = y
    return {"out0": out.reshape(ho * wo * nbo, 128)}
