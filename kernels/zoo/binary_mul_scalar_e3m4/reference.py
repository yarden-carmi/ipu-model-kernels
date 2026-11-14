import torch


def reference(**kw):
    """out0 = in0 * const, elementwise over the first numel elements.

    Lanes past the tensor's last element are padding and are zero, matching
    the store's DS-masked rows.
    """
    in0 = kw["in0"]
    const = float(kw["const"])
    numel = int(kw["numel"])
    out = in0 * const
    flat = out.reshape(-1)
    if flat.numel() > numel:
        flat[numel:] = 0.0
    return {"out0": out}
