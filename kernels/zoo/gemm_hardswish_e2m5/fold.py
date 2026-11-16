import torch

def fold(module, **params):
    # Weights arrive as the operation's own [n, k]; the kernel reads them
    # transposed to [k, 128] with n along the 128 lanes, zero padded. Bias is
    # padded the same way.
    k, n = int(params["k"]), int(params["n"])
    w = torch.zeros(k, 128, dtype=torch.float32)
    w[:, :n] = module.weight.detach().t()
    result = {"w": w}
    if params["bias"]:
        b = torch.zeros(128, dtype=torch.float32)
        b[:n] = module.bias.detach()
        result["b"] = b
    return result
