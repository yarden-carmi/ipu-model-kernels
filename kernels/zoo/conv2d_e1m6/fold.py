import torch


def fold(module, **params):
    """Weights to rows of 128 input channels: row co*Sall + 0 = bias (lane 0), row co*Sall + 1 + (ky*kw + kx)
    = the input channels of weights[co, :, ky, kx] (lanes past cin are zero)."""
    w = module.weights.to(torch.float64)
    cout, cin, kh, kw = w.shape
    taps = kh * kw
    rows = torch.zeros(cout, taps + 1, 128, dtype=torch.float64)
    rows[:, 1:, :cin] = w.permute(0, 2, 3, 1).reshape(cout, taps, cin)
    if params.get('bias'):
        b = getattr(module, 'bias_vec', None)
        if b is None:
            b = getattr(module, 'bias')
        rows[:, 0, 0] = b.to(torch.float64).reshape(-1)[:cout]
    return {'weights': rows.reshape(-1, 128)}
