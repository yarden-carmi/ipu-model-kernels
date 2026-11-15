import torch

def reference(**kw):
    ids = kw["in0"].reshape(-1)[:kw["s0_rows"]]
    vocab = torch.arange(kw["s0_n"], dtype=ids.dtype, device=ids.device)
    selector = (ids[:, None] == vocab[None, :]).to(torch.float64)
    weights = kw["weights"]
    result = selector[:, :kw["s1_k"]] @ weights
    result = result.reshape(1, kw["s1_m"], kw["s1_n"])
    return {"out0": result + kw["add0"] + kw["add1"]}
