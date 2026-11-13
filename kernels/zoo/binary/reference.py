import torch


def reference(a, const, **_):
    return {"y": a * const}
