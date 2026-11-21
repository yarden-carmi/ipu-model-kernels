import torch
import torch.nn.functional as F


def reference(**kw):
    cin, cout = int(kw['cin']), int(kw['cout'])
    h, w = int(kw['h']), int(kw['w'])
    kh, kwd = int(kw['kh']), int(kw['kw'])
    stride, padding = int(kw['stride']), int(kw['padding'])
    taps = kh * kwd
    sall = taps + 1
    x = kw['in0'].to(torch.float64).reshape(h, w, 128)[..., :cin].permute(2, 0, 1)[None]
    # weights arrive folded: row co*sall (bias, lane 0) then row co*sall + 1 + (ky*kwd + kx), lanes = input channels
    wf = kw['weights'].to(torch.float64).reshape(cout, sall, 128)
    weight = wf[:, 1:, :cin].reshape(cout, kh, kwd, cin).permute(0, 3, 1, 2).contiguous()
    bias = wf[:, 0, 0].clone() if kw.get('bias') else None
    y = F.conv2d(x, weight, bias, stride=stride, padding=padding)[0]  # (cout, ho, wo)
    ho, wo = y.shape[1], y.shape[2]
    out = torch.zeros(cout, ho, 128, dtype=torch.float64)
    out[:, :, :wo] = y
    return {'out0': out.reshape(cout * ho, 128)}
