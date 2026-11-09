# deit_small_patch16_224.fb_in1k

- domain: vision-transformer, family: deit, size: 22M, params at full depth: 22.1M
- canonical: deit_small_patch16_224.fb_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=197,n=384}` | 12 | 116,195,328 | cpu | cpu | - |
| `linear{bias=1,k=384,m=197,n=1536}` | 12 | 116,195,328 | cpu | cpu | - |
| `linear{bias=1,k=384,m=197,n=1152}` | 12 | 87,146,496 | cpu | cpu | - |
| `attention{b=1,d=64,heads=6,kv=197,q=197}` | 12 | 29,805,312 | cpu | cpu | - |
| `linear{bias=1,k=384,m=197,n=384}` | 12 | 29,048,832 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=384,dilation=1,groups=1,h=224,kh=16,kw=16,out_elements=75264,padding=0,stride=16,w=224}` | 1 | 57,802,752 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1,n=1000}` | 1 | 384,000 | cpu | cpu | - |
| `add{broadcast=0,numel=75648,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=384,layout=channels_last,tokens=197}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `gelu{numel=302592}` | 12 | 0 | cpu | cpu | - |
| `aten{numel=75264,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=75648}` | 1 | 0 | cpu | cpu | - |

