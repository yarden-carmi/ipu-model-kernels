def fold(module, **params):
    import torch
    n, k = int(params["s1_n"]), int(params["s1_k"])
    nb = (n + 127) // 128
    w = module.weight.detach().to(torch.float32)
    # Inputs are row-major with the output columns occupying the lanes.
    return {"w": w[:, :n].contiguous().reshape(k * nb, 128)}
