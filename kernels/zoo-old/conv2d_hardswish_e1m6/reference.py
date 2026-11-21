import torch
import torch.nn.functional as F

def reference(**p):
    ci, co = p['cin'], p['cout']
    nb = (ci + 127) // 128
    cp = ((co + 127) // 128) * 128
    h, w = p['h'], p['w']
    r = p['in0'][:h * w * nb].reshape(h * w, nb, 128)
    x = torch.cat([r[:, b, :min(128, ci - b * 128)] for b in range(nb)], dim=1)
    x = x.reshape(h, w, ci).permute(2, 0, 1).unsqueeze(0)
    weight = p['weights'].reshape(p['kh'], p['kw'], ci // p['groups'], cp)[..., :co].permute(3, 2, 0, 1).contiguous()
    b = p['bias_vec'][:co] if p['bias'] else None
    y = F.hardswish(F.conv2d(x, weight, b, stride=p['stride'], padding=p['padding'], groups=p['groups']))[0].permute(1, 2, 0)
    return {'out0': F.pad(y, (0, cp-co))}
