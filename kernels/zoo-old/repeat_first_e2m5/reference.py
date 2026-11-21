def reference(in0, rows, channels, **kw):
    return {"out0": in0[:1, :channels].expand(4, rows, channels).contiguous()}
