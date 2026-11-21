import torch
import torch.nn.functional as F

def reference(**p):
    ci, co = p['cin'], p['cout']
    cp = ((co + 127) // 128) * 128
    x = p['in0'][..., :ci].permute(2, 0, 1).unsqueeze(0)
    weight = p['weights'].reshape(p['kh'], p['kw'], ci // p['groups'], cp)[..., :co].permute(3, 2, 0, 1).contiguous()
    b = p['bias_vec'][:co] if p['bias'] else None
    y = F.silu(F.conv2d(x, weight, b, stride=p['stride'], padding=p['padding'], groups=p['groups']))[0].permute(1, 2, 0)
    return {'out0': F.pad(y, (0, cp-co))}
