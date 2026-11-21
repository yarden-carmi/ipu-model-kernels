import torch

def fold(module, **params):
    c = params['s0_channels']
    g = torch.zeros(128)
    g[:c] = module.gamma.detach().reshape(-1)
    w = module.weights.detach().reshape(params['s1_cout'],params['s1_cin'])
    padded = torch.zeros(w.shape[0], ((w.shape[1]+127)//128)*128)
    padded[:,:w.shape[1]] = w
    return {'gamma':g, 'weights':padded.reshape(w.shape[0],-1,128)}
