import torch

def reference(**kw):
    # terra_integer_triangle: tri[m, j] = clamp(1 - |trunc(x[m]) - j|, min=0), then gemm with w[k, n].
    tokens, vocab, n = int(kw['s0_tokens']), int(kw['s0_vocab']), int(kw['s1_n'])
    x = kw['in0'].to(torch.float64).reshape(-1)[:tokens].to(torch.int64)
    j = torch.arange(vocab, dtype=torch.int64).reshape(1, vocab)
    tri = (1 - (x.reshape(-1, 1) - j).abs()).clamp(min=0).to(torch.float64)
    w = kw['w'].to(torch.float64).reshape(vocab, n)
    out = tri @ w
    return {'out0': out.reshape(-1, 128)}
