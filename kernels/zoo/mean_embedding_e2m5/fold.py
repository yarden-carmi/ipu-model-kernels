def fold(module, **params):
    return {"mean": module.table.float().mean(dim=0).to(module.table.dtype).reshape(-1, 128)}
