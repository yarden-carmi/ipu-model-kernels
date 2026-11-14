import torch
import torch.nn.functional as F

def reference(**kw):
    cin, cout, groups = int(kw['cin']), int(kw['cout']), int(kw['groups'])
    h, w, kh, kx = (int(kw[k]) for k in ('h', 'w', 'kh', 'kw'))
    nbi, nbo = (cin + 127) // 128, (cout + 127) // 128
    x = kw['in0'].to(torch.float64).reshape(h, w, nbi * 128)[..., :cin].permute(2, 0, 1)[None]
    weight = kw['weights'].to(torch.float64).reshape(kh, kx, cin // groups, nbo * 128)[..., :cout].permute(3, 2, 0, 1).contiguous()
    bias = kw['bias_vec'].to(torch.float64).reshape(-1)[:cout] if kw['bias'] else None
    y = F.silu(F.conv2d(x, weight, bias, stride=int(kw['stride']), padding=int(kw['padding']), groups=groups))[0].permute(1, 2, 0)
    out = torch.zeros(y.shape[0], y.shape[1], nbo * 128, dtype=torch.float64)
    out[..., :cout] = y
    return {'out0': out.reshape(-1, 128)}
