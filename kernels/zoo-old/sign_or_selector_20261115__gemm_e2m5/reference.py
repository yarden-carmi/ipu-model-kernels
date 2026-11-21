import torch

def reference(**kw):
    # sign_or_selector: one-hot selector sel[m, k] = (x[m] == k), via the sign of d | -d.
    # gemm with the selector: out[m, n] = sum_k sel[m, k] * w[k, n] = w[x[m], n] (zero row if x out of range).
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    ids = kw['in0'].to(torch.float64).reshape(-1)[:tokens].long()
    d = ids.reshape(tokens, 1) - torch.arange(vocab, dtype=torch.int64).reshape(1, vocab)
    sel = ((torch.bitwise_right_shift(torch.bitwise_or(d, -d), 63)) + 1).to(torch.float64)
    w = kw['w'].to(torch.float64).reshape(vocab, n)
    out = sel @ w
    return {'out0': out.reshape(-1, 128)}
