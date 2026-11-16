def fold(module, **params):
    import torch
    layers = [m for m in module.modules() if hasattr(m, 'weight') and isinstance(m.weight, torch.Tensor) and m.weight.ndim == 2]
    assert len(layers) == 3
    nbs = [int(params["s0_n"]) // 128, int(params["s1_n"]) // 128, int(params["s2_n"]) // 128]
    result = {}
    rows = []
    for i, (mod, nb) in enumerate(zip(layers, nbs)):
        w = mod.weight.detach()
        n, k = w.shape
        no = nb * 128
        wp = torch.zeros(k, no, dtype=torch.float32)
        wp[:, :n] = w.t().to(torch.float32)
        result[f'w{i}'] = w.contiguous() if i == 1 else wp.reshape(-1, 128)
        bp = torch.zeros(no, dtype=torch.float32)
        b = getattr(mod, 'bias', None)
        if b is not None:
            bp[:n] = b.detach().to(torch.float32)
        rows.append(bp)
    result['biases'] = torch.cat(rows, dim=0).reshape(-1, 128).contiguous()
    return result
