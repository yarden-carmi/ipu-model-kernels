import torch
def fold(module, **p):
    owners=list(module.modules()) if hasattr(module,'modules') else [module]
    def get(names,shape):
        for o in owners:
            for n in names:
                t=getattr(o,n,None)
                if isinstance(t,torch.Tensor) and tuple(t.shape)==tuple(shape): return t.detach()
        raise ValueError(str((names,shape)))
    k,n=p['s1_k'],p['s1_n']
    w=get(('weight','table'),(k,n))
    adds=[]
    seen=set()
    for o in owners:
        values=list(vars(o).values())
        if hasattr(o,'named_buffers'):
            values += [t for _,t in o.named_buffers(recurse=False)]
            values += [t for _,t in o.named_parameters(recurse=False)]
        for t in values:
            if isinstance(t,torch.Tensor) and t.numel()==p['s1_m']*n and id(t) not in seen:
                seen.add(id(t))
                adds.append(t.detach().reshape(p['s1_m'],n))
    if not adds:
        raise ValueError('missing folded GEMM additions')
    return dict(w=w.contiguous(),add=sum(adds).contiguous(),gamma=get(('gamma','weight'),(n,)),beta=get(('beta','bias'),(n,)))
