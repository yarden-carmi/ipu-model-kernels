import torch

def rounded(x):
    r = x.float().reshape(-1,128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1,keepdim=True).values
    step = 2.0**(torch.maximum(e,scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step, 2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(x.shape)

def reference(**kw):
    data = kw['constants'].flatten()
    pos = 0
    weights = []
    for i in range(3):
        k,n = kw[f's{i}_k'],kw[f's{i}_n']
        weights.append(data[pos:pos+k*n].reshape(k,n))
        pos += k*n
    biases = []
    for i in range(3):
        n = kw[f's{i}_n']
        biases.append(data[pos:pos+n]); pos += n
    ops = []
    for i in [3,5,7,9]:
        n = kw[f's{i}_inner']
        ops.append(data[pos:pos+n]); pos += n
    result = {}
    x = kw['in0'].reshape(kw['s0_m'],kw['s0_k'])
    for i in range(3):
        m,n = kw[f's{i}_m'],kw[f's{i}_n']
        y = x @ weights[i]
        if kw[f's{i}_bias']: y = y + biases[i]
        y = rounded(y).reshape(m,n//128,128).permute(1,0,2).contiguous()
        if i < 2:
            c,s = ops[2*i:2*i+2]
            a = rounded((y.flatten()*c.repeat(y.numel()//c.numel())).reshape(y.shape))
            rot = torch.cat([-y[...,64:],y[...,:64]],-1)
            b = rounded((rot.flatten()*s.repeat(y.numel()//s.numel())).reshape(y.shape))
            y = a+b
        result[f'out{i}'] = y.unsqueeze(0)
    return result
