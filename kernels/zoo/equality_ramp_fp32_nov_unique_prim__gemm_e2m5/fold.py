def fold(module, **params):
    return {"weights": (module.weight * 0.5).contiguous()}
