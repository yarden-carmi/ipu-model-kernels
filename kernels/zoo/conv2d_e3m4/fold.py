import torch


def fold(module, **params):
    """Weights to rows of 128 input channels: row co*Sall + s, one per (tap, channel block) in
    (ky, kx, ib) order, then one bias row per output channel (lane 0 = bias, used with a 1.0 scalar)."""
    w = module.weights.to(torch.float64)
    cout, cin, kh, kw = w.shape
    nbi = (cin + 127) // 128
    taps = kh * kw * nbi
    rows = torch.zeros(cout, taps + 1, 128, dtype=torch.float64)
    if cin == 3 and params.get('padding', 0) == 0 and not params.get('bias'):
        packed = w.permute(0, 2, 3, 1).reshape(cout, -1)
        blocks = (kh * kw * cin + 127) // 128
        out = torch.zeros(cout, blocks * 128, dtype=torch.float64)
        out[:, :packed.shape[1]] = packed
        rows.reshape(-1)[:out.numel()] = out.reshape(-1)
        return {'weights': rows.reshape(-1, 128)}
    for co in range(cout):
        for ky in range(kh):
            for kx in range(kw):
                for ib in range(nbi):
                    s = (ky * kw + kx) * nbi + ib
                    blk = w[co, ib * 128:(ib + 1) * 128, ky, kx]
                    rows[co, s, :blk.numel()] = blk
        if params.get('bias'):
            b = getattr(module, 'bias_vec', None)
            if b is None:
                b = getattr(module, 'bias')
            rows[co, taps, 0] = b.to(torch.float64).reshape(-1)[co]
    return {'weights': rows.reshape(-1, 128)}
