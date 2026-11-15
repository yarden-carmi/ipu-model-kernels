import torch


def reference(**kw):
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    w = kw['w'].to(torch.float64).reshape(-1, n)  # [k, n]: row k is weight row for vocab id k
    k_dim = w.shape[0]
    # eq_static_terra_new_prim: one-hot selector rows against the vocab ramp
    sel = (ids.reshape(-1, 1) == torch.arange(k_dim, dtype=torch.float64).reshape(1, -1)).to(torch.float64)
    # gemm: out[m, n] = sum_k sel[m, k] * w[k, n]
    out = sel @ w
    return {'out0': out.reshape(-1, 128)}
