import torch

def fold(module, **params):
    k, n = int(params["k"]), int(params["n"])
    nb = (n + 127) // 128
    w = torch.zeros(k, nb * 128)
    w[:, :n] = module.weight.detach().t()
    result = {"w": w.reshape(k, nb, 128).permute(1, 0, 2).contiguous()}
    if params["bias"]:
        b = torch.zeros(nb * 128)
        b[:n] = module.bias.detach()
        result["b"] = b.reshape(nb, 128)
    return result
