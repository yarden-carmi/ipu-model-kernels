import torch
def reference(**kw):
    r,c=kw['s0_rows'],kw['s0_channels']
    x=kw['in0'][0,0].t()[:r,:c]
    y=x*torch.rsqrt(x.square().mean(-1,keepdim=True)+kw['s0_eps'])*kw['gamma']
    m,k,n=kw['s1_m'],kw['s1_k'],kw['s1_n']
    z=kw['in1'].reshape(m,k)@kw['w'].reshape(k,n)
    if kw['s1_bias']:
        z=z+kw['b']
    o=torch.zeros(1,1,n,((m+127)//128)*128,dtype=torch.float64)
    o[0,0,:,:m]=z.t()
    return {'out0':y.reshape(r,1,1,c),'out1':o}
