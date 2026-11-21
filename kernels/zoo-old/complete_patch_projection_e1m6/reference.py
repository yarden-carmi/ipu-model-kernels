def reference(in0, w, b, batch, channels, features, **kw):
    import torch
    a = in0[..., :14].reshape(batch, features).float()
    weight = w.reshape(features, channels).float()
    return {"out0": torch.addmm(b.float(), a, weight).double()}
