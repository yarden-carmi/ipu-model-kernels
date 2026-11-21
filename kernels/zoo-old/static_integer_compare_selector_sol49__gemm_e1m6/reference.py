import torch


def reference(**kw):
    ids = kw["in0"].reshape(-1)[:kw["s0_tokens"]]
    vocab = torch.arange(kw["s0_vocab"], dtype=ids.dtype, device=ids.device)
    selector = (ids[:, None] == vocab[None, :]).to(torch.float64)
    result = selector[:, :kw["s1_k"]] @ kw["weights"]
    return {"out0": result.reshape(1, kw["s1_m"], kw["s1_n"])}
