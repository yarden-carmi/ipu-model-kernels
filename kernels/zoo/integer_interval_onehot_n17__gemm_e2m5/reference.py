import torch

def reference(**kw):
    # integer_interval_onehot_n17: onehot[m, j] = (ids[m] >= j) & (ids[m] < j + 1), then gemm with w.
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    x = kw['in0'].to(torch.float64).reshape(-1)[:tokens]
    j = torch.arange(vocab, dtype=torch.float64).reshape(1, vocab)
    sel = ((x.reshape(-1, 1) >= j) & (x.reshape(-1, 1) < j + 1)).to(torch.float64)
    w = kw['w'].to(torch.float64).reshape(vocab, n)
    out = sel @ w
    return {'out0': out.reshape(-1, 128)}
