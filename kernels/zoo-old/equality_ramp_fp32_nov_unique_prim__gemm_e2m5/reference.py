def reference(**kw):
    import torch
    tokens = kw["in0"].reshape(-1)[:kw["s0_tokens"]]
    vocab = kw["s0_vocab"]
    # Equality selectors have at most one nonzero entry. This is exactly their
    # matrix product with the finite constant table, without materializing it.
    valid = (tokens == tokens.floor()) & (tokens >= 0) & (tokens < vocab)
    result = torch.zeros(tokens.numel(), kw['s1_n'], dtype=torch.float64, device=tokens.device)
    result[valid] = kw['weights'][tokens[valid].long()] * 2
    return {"out0": result.reshape(1, kw['s1_m'], kw['s1_n'])}
