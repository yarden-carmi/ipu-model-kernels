import torch

def reference(**kw):
    c = kw['numel'] // 3136
    result = torch.relu(kw['in0'][0, :, :, :56] + kw['in1'][0, :, :, :56])
    out = torch.zeros((1, (c + 127)//128, 56, 56, 128), dtype=result.dtype)
    for ch in range(c):
        out[0, ch//128, :, :, ch%128] = result[ch]
    return {'out0': out}
