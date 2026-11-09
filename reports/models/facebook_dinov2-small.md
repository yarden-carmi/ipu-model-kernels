# facebook/dinov2-small

- domain: vision-transformer, family: dinov2, size: 22M, params at full depth: 22.1M
- canonical: facebook/dinov2-small
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"encoder.layer": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=1370,n=384}` | 12 | 808,058,880 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1370,n=1536}` | 12 | 808,058,880 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1370,n=384}` | 48 | 202,014,720 | cpu | cpu | - |
| `bmm{b=6,k=1370,m=1370,n=64}` | 12 | 720,729,600 | cpu | cpu | - |
| `bmm{b=6,k=64,m=1370,n=1370}` | 12 | 720,729,600 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=384,dilation=1,groups=1,h=518,kh=14,kw=14,out_elements=525696,padding=0,stride=14,w=518}` | 1 | 309,109,248 | cpu | cpu | - |
| `add{broadcast=0,numel=526080,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=384,layout=channels_last,tokens=1370}` | 25 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=526080,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `gelu{numel=2104320}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=11261400,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=1370,rows=8220}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `aten{numel=525696,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=526080}` | 1 | 0 | cpu | cpu | - |

