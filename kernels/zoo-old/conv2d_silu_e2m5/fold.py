import torch
def fold(module, **params):
    w = module.weights.permute(0,2,3,1).reshape(-1)
    out = torch.zeros(w.numel(),128,dtype=w.dtype)
    out[:,0] = w
    if params['groups'] == 1:
        wt = module.weights.permute(0,2,3,1)
        out = torch.zeros(*wt.shape[:-1], ((params['cin']+127)//128)*128, dtype=wt.dtype)
        out[...,:params['cin']] = wt
        out = out.reshape(-1,128)
    b = torch.zeros(params['cout'],128,dtype=w.dtype)
    if params.get('bias',True): b[:,0] = module.bias
    return {'weights':out,'bias_vec':b}
