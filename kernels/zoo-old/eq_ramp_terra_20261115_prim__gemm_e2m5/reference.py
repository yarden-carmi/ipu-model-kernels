import torch


def reference(**kw):
    tokens = kw["in0"].to(torch.float64).reshape(-1)[:kw["s0_tokens"]]
    indices = torch.arange(kw["s0_vocab"], dtype=torch.float64)
    sel = (tokens[:, None] == indices[None, :]).to(torch.float64)
    out = sel @ kw["weights"].to(torch.float64)
    out = sel @ kw["weights"].to(torch.float64)
    return {"out0": out.reshape(1, kw["s1_m"], kw["s1_n"])}
