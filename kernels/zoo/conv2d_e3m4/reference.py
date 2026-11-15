import torch
import torch.nn.functional as F


def reference(**kw):
    cin, cout = int(kw['cin']), int(kw['cout'])
    h, w = int(kw['h']), int(kw['w'])
    kh, kwd = int(kw['kh']), int(kw['kw'])
    stride, padding = int(kw['stride']), int(kw['padding'])
    nbi = (cin + 127) // 128
    taps = kh * kwd * nbi
    sall = taps + 1
    x = kw['in0'].to(torch.float64).reshape(h, w, nbi * 128)[..., :cin].permute(2, 0, 1)[None]
    # weights arrive folded: row co*sall + s (s = (ky*kwd+kx)*nbi + ib, bias last), lanes = input channels
    wf = kw['weights'].to(torch.float64).reshape(cout, sall, 128)
    weight = torch.zeros(cout, cin, kh, kwd, dtype=torch.float64)
    for ky in range(kh):
        for kx in range(kwd):
            for ib in range(nbi):
                s = (ky * kwd + kx) * nbi + ib
                lanes = min(128, cin - ib * 128)
                weight[:, ib * 128:ib * 128 + lanes, ky, kx] = wf[:, s, :lanes]
    bias = wf[:, taps, 0].clone() if kw.get('bias') else None  # bias row: lane 0 of row taps
    y = F.conv2d(x, weight, bias, stride=stride, padding=padding)[0]  # (cout, ho, wo)
    ho, wo = y.shape[1], y.shape[2]
    out = torch.zeros(cout, wo, 128, dtype=torch.float64)
    out[:, :, :ho] = y.transpose(1, 2)
    return {'out0': out.reshape(cout * wo, 128)}
