# facebook/DiT-XL-2-256

- domain: diffusion, family: dit, size: 675M, params at full depth: 749.8M
- canonical: facebook/DiT-XL-2-256
- depth scaling: `{"_scales_from": [1, 1], "num_layers": [28, 2], "scales": {"transformer_blocks": 14.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1152,m=256,n=1152}` | 112 | 339,738,624 | cpu | cpu | - |
| `linear{bias=1,k=1152,m=256,n=4608}` | 28 | 1,358,954,496 | cpu | cpu | - |
| `linear{bias=1,k=4608,m=256,n=1152}` | 28 | 1,358,954,496 | cpu | cpu | - |
| `attention{b=1,d=72,heads=16,kv=256,q=256}` | 28 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=1152,m=1,n=6912}` | 28 | 7,962,624 | cpu | cpu | - |
| `linear{bias=1,k=1152,m=1,n=1152}` | 42 | 1,327,104 | cpu | cpu | - |
| `linear{bias=1,k=256,m=1,n=1152}` | 42 | 294,912 | cpu | cpu | - |
| `linear{bias=1,k=1152,m=256,n=32}` | 1 | 9,437,184 | cpu | cpu | - |
| `conv2d{bias=1,cin=4,cout=1152,dilation=1,groups=1,h=32,kh=2,kw=2,out_elements=294912,padding=0,stride=2,w=32}` | 1 | 4,718,592 | cpu | cpu | - |
| `linear{bias=1,k=1152,m=1,n=2304}` | 1 | 2,654,208 | cpu | cpu | - |
| `mul{broadcast=1,numel=294912,operands=tensor}` | 113 | 0 | cpu | cpu | - |
| `concat{numel=256}` | 84 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=128,operands=scalar}` | 84 | 0 | cpu | cpu | - |
| `silu{numel=1152}` | 71 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `add{broadcast=0,numel=1152,operands=scalar}` | 57 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=294912,operands=tensor}` | 57 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=294912,operands=tensor}` | 57 | 0 | cpu | cpu | - |
| `layernorm{channels=1152,layout=channels_last,tokens=256}` | 57 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1152,operands=tensor}` | 42 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `cos{numel=128}` | 42 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=128,operands=scalar}` | 42 | 0 | cpu | cpu | - |
| `embedding{dim=1152,tokens=1,vocab=1001}` | 42 | 0 | cpu | cpu | - |
| `exp{numel=128}` | 42 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=128,operands=tensor}` | 42 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 42 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=294912,operands=scalar}` | 28 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=1179648}` | 28 | 0 | cpu | cpu | - |
| `aten{numel=294912,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=8192,schema=aten::einsum}` | 1 | 0 | cpu | cpu | - |

