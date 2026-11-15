import torch


def reference(**kw):
    tokens = kw["in0"].reshape(-1)[:kw["s0_tokens"]]
    indices = torch.arange(kw["s0_vocab"], dtype=tokens.dtype, device=tokens.device)
    selector = (tokens[:, None] == indices[None, :]).to(torch.float64)
    # Constants are physically transposed, with output channels along lanes.
    result = selector @ kw["weights"]
    if kw["s1_bias"]:
        result = result + kw["bias"]
    result = result.reshape(1, kw["s1_m"], kw["s1_n"])
    return {"out0": result + kw["add0"] + kw["add1"]}
