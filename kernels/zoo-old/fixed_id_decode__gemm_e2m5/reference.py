import torch


def reference(**kw):
    tokens = int(kw['s0_tokens'])
    vocab = int(kw['s0_vocab'])
    m = int(kw['s1_m'])
    n = int(kw['s1_n'])
    k = int(kw['s1_k'])
    # fixed_id_decode: truncate the token ids to int64 and compare against the
    # vocabulary ramp, casting the predicates to float.
    x = kw['in0'].to(torch.float64).reshape(-1)[:tokens]
    ids = x.to(torch.int64)
    ramp = torch.arange(vocab, dtype=torch.int64, device=ids.device)
    sel = (ids[:, None] == ramp[None, :]).to(torch.float64)
    # gemm: weights arrive vocabulary-major, [k, n], so n runs along the lanes.
    w = kw['weights'].to(torch.float64).reshape(k, n)
    out = sel @ w
    if kw['s1_bias']:
        out = out + kw['bias'].to(torch.float64).reshape(n)
    # the two adds folded into the gemm's constants at home
    out = out + kw['add0'].to(torch.float64).reshape(m, n)
    out = out + kw['add1'].to(torch.float64).reshape(m, n)
    return {'out0': out.reshape(1, m, n)}
