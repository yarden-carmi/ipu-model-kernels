import torch

def rounded(x):
    r = x.float().reshape(-1,128).double()
    a = r.abs()
    e = torch.floor(torch.log2(a.clamp_min(2.0**-126)))
    scale = e.max(-1,keepdim=True).values
    step = 2.0**(torch.maximum(e,scale-2)-5)
    y = torch.minimum(torch.floor(a/step+0.5)*step,2.0**scale*(2-1/32))
    return (y*r.sign()).reshape(x.shape)

def reference(**kw):
    ids = kw['in0'].reshape(-1).long()
    table = kw['table'].float()
    vocab, dim = table.shape
    h = (vocab + 511) // 512
    padded = torch.nn.functional.pad(table, (0, 0, 0, h*512-vocab))
    packed = padded.reshape(h,512,dim).permute(1,0,2).reshape(512,h*dim)
    lo = (ids.remainder(512)[:,None] == torch.arange(512)[None,:]).float()
    partial = (lo @ packed).reshape(ids.numel(),h,dim)
    hi = (torch.div(ids,512,rounding_mode='floor')[:,None] == torch.arange(h)[None,:]).float()
    a = torch.bmm(hi[:,None,:],partial).reshape(ids.numel(),dim).double()
    x = kw['in1'].reshape(-1).long()
    b = torch.ones_like(x)
    s,c = x ^ b,(x & b) << 1
    for _ in range(9):
        s,c = s ^ c,(s & c) << 1
    selector = (s[:,None] == torch.arange(kw['s2_vocab'])[None,:]).float()
    y = (selector @ kw['w'].float()).double()
    # The mux drives only the placeholder input of the singleton primitive.
    v = kw['v'].reshape(1,-1).expand(kw['s5_tokens'],-1)
    z = rounded(a + y)
    z = rounded(z + v)
    mu = z.mean(-1,keepdim=True)
    var = (z-mu).square().mean(-1,keepdim=True)
    out = (z-mu) / torch.sqrt(var+kw['s8_eps'])
    return {'out0': (out*kw['gamma']+kw['beta']).unsqueeze(0)}
