# vit_base_patch16_224.augreg2_in21k_ft_in1k

- domain: vision-transformer, family: vit, size: 86M, params at full depth: 86.6M
- canonical: vit_base_patch16_224.augreg2_in21k_ft_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=197,n=768}` | 12 | 464,781,312 | cpu | cpu | - |
| `linear{bias=1,k=768,m=197,n=3072}` | 12 | 464,781,312 | cpu | cpu | - |
| `linear{bias=1,k=768,m=197,n=2304}` | 12 | 348,585,984 | cpu | cpu | - |
| `linear{bias=1,k=768,m=197,n=768}` | 12 | 116,195,328 | cpu | cpu | - |
| `attention{b=1,d=64,heads=12,kv=197,q=197}` | 12 | 59,610,624 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=768,dilation=1,groups=1,h=224,kh=16,kw=16,out_elements=150528,padding=0,stride=16,w=224}` | 1 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=1000}` | 1 | 768,000 | cpu | cpu | - |
| `add{broadcast=0,numel=151296,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=197}` | 25 | 0 | cpu | cpu | - |
| `gelu{numel=605184}` | 12 | 0 | cpu | cpu | - |
| `aten{numel=150528,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=151296}` | 1 | 0 | cpu | cpu | - |

