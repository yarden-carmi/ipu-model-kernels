import torch
def reference(**kw):
    x=kw['in0'].reshape(-1,1)
    a=(x==torch.arange(kw['s0_vocab'],device=x.device)).double() @ kw['w0']
    pos=torch.clamp(kw['in1'].float()+1,max=255).long().reshape(-1,1)
    b=(pos==torch.arange(kw['s3_vocab'],device=x.device)).double() @ kw['w1']
    if kw['s4_bias']: b=b+kw['b']
    index=kw['in1']
    selected=None
    for start in range(0,kw['table'].shape[1],53):
        z=kw['table'][:,start:start+53].mean(1,keepdim=True).expand(index.shape)
        selected=z if selected is None else torch.where(index>=start,z,selected)
    c=kw['v'].reshape(1,-1).expand(kw['s6_tokens'],-1).clone()
    return dict(out0=a.reshape(1,kw['s1_m'],kw['s1_n']),out1=b.reshape(1,kw['s4_m'],kw['s4_n']),out2=c.reshape(1,kw['s6_tokens'],kw['s6_dim']))
