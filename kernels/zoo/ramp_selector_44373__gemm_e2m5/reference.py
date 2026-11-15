def reference(**kw):
    import torch
    tokens = kw["in0"].reshape(-1)
    vocab = kw["s0_vocab"]
    selector = (tokens[:, None] == torch.arange(vocab, device=tokens.device)[None, :]).to(torch.float64)
    w = kw["w"].reshape(kw["s1_k"], -1)[:vocab]
    out = selector @ w
    if kw["s1_bias"]:
        out = out + kw["b"][:kw["s1_n"]]
    return {"out0": out.reshape(-1, 128)}
