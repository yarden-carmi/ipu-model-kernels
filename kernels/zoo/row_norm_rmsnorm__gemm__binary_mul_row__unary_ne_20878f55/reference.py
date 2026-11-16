import torch
def rounded(x):
    r=x.float().reshape(-1,128).double(); a=r.abs()
    e=torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale=e.max(-1,keepdim=True).values
    step=2.0**(torch.maximum(e,scale-2)-5)
    return (torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))*r.sign()).reshape(x.shape)
def reference(**kw):
    d=kw['constants'].flatten(); c=d[:128]; pos=128
    m,k,n=kw['s1_m'],kw['s1_k'],kw['s1_n']
    w=d[pos:pos+k*n].reshape(k,n); pos+=k*n
    b=d[pos:pos+n]; pos+=n
    ops=[]
    for i in [2,4,6,8]:
        z=kw[f's{i}_inner']; ops.append(d[pos:pos+z]); pos+=z
    x=kw['in0'][0,0].t()[:kw['s0_rows']]
    norm=x*torch.rsqrt(x.square().mean(-1,keepdim=True)+kw['s0_eps'])*c
    y=kw['in1'].reshape(m,k)@w
    if kw['s1_bias']: y=y+b
    y=rounded(y).reshape(m,n//128,128).permute(1,0,2).contiguous()
    out={'out0':norm.reshape(-1,1,1,128)}
    for i,y in enumerate([y,kw['in2']]):
        a,s=ops[2*i:2*i+2]
        first=rounded((y.flatten()*a.repeat(y.numel()//a.numel())).reshape(y.shape))
        rot=torch.cat([-y[...,64:],y[...,:64]],-1)
        second=rounded((rot.flatten()*s.repeat(y.numel()//s.numel())).reshape(y.shape))
        out[f'out{i+1}']=(first+second).reshape(kw['in2'].shape if i else (1,n//128,m,128))
    return out
