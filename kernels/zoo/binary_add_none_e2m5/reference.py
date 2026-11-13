import torch


def reference(in0, in1, **_):
    return {"out0": in0 + in1}
