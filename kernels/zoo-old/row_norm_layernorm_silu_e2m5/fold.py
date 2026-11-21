import torch
def fold(module, **params):
    r, c = params['rows'], params['channels']
    p = r*c//128
    g = module.gamma.reshape(-1)[:c].repeat(r).reshape(128,p).T.contiguous()
    b = module.beta.reshape(-1)[:c].repeat(r).reshape(128,p).T.contiguous()
    masks = torch.zeros(r,128)
    for i in range(r):
        masks[i,i*(128//r):(i+1)*(128//r)] = 1
    return {'gamma':g,'beta':b}
