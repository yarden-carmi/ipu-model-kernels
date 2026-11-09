# stable-diffusion-v1-5/stable-diffusion-v1-5:vae

- domain: diffusion, family: sd-vae, size: 84M, params at full depth: 83.7M
- canonical: stable-diffusion-v1-5/stable-diffusion-v1-5:vae
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=128,kh=3,kw=3,out_elements=8388608,padding=1,stride=1,w=128}` | 10 | 38,654,705,664 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=128,dilation=1,groups=1,h=512,kh=3,kw=3,out_elements=33554432,padding=1,stride=1,w=512}` | 9 | 38,654,705,664 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=256,dilation=1,groups=1,h=256,kh=3,kw=3,out_elements=16777216,padding=1,stride=1,w=256}` | 8 | 38,654,705,664 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=2097152,padding=1,stride=1,w=64}` | 18 | 9,663,676,416 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=256,cout=256,dilation=1,groups=1,h=512,kh=3,kw=3,out_elements=67108864,padding=1,stride=1,w=512}` | 1 | 154,618,822,656 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=256,kh=3,kw=3,out_elements=33554432,padding=1,stride=1,w=256}` | 1 | 154,618,822,656 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=128,dilation=1,groups=1,h=512,kh=3,kw=3,out_elements=33554432,padding=1,stride=1,w=512}` | 1 | 77,309,411,328 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=256,dilation=1,groups=1,h=256,kh=3,kw=3,out_elements=16777216,padding=1,stride=1,w=256}` | 1 | 77,309,411,328 | cpu | cpu | - |
| `attention{b=1,d=512,heads=1,kv=4096,q=4096}` | 2 | 17,179,869,184 | cpu | cpu | - |
| `conv2d{bias=1,cin=128,cout=256,dilation=1,groups=1,h=256,kh=3,kw=3,out_elements=16777216,padding=1,stride=1,w=256}` | 1 | 19,327,352,832 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=512,dilation=1,groups=1,h=128,kh=3,kw=3,out_elements=8388608,padding=1,stride=1,w=128}` | 1 | 19,327,352,832 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=128,dilation=1,groups=1,h=513,kh=3,kw=3,out_elements=8388608,padding=0,stride=2,w=513}` | 1 | 9,663,676,416 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=256,dilation=1,groups=1,h=257,kh=3,kw=3,out_elements=4194304,padding=0,stride=2,w=257}` | 1 | 9,663,676,416 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=129,kh=3,kw=3,out_elements=2097152,padding=0,stride=2,w=129}` | 1 | 9,663,676,416 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=128,dilation=1,groups=1,h=512,kh=1,kw=1,out_elements=33554432,padding=0,stride=1,w=512}` | 1 | 8,589,934,592 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=256,dilation=1,groups=1,h=256,kh=1,kw=1,out_elements=16777216,padding=0,stride=1,w=256}` | 1 | 8,589,934,592 | cpu | cpu | - |
| `linear{bias=1,k=512,m=4096,n=512}` | 8 | 1,073,741,824 | cpu | cpu | - |
| `conv2d{bias=1,cin=128,cout=256,dilation=1,groups=1,h=256,kh=1,kw=1,out_elements=16777216,padding=0,stride=1,w=256}` | 1 | 2,147,483,648 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=512,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=8388608,padding=0,stride=1,w=128}` | 1 | 2,147,483,648 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=3,dilation=1,groups=1,h=512,kh=3,kw=3,out_elements=786432,padding=1,stride=1,w=512}` | 1 | 905,969,664 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=128,dilation=1,groups=1,h=512,kh=3,kw=3,out_elements=33554432,padding=1,stride=1,w=512}` | 1 | 905,969,664 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=8,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=32768,padding=1,stride=1,w=64}` | 1 | 150,994,944 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=4,cout=512,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=2097152,padding=1,stride=1,w=64}` | 1 | 75,497,472 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=8,cout=8,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=32768,padding=0,stride=1,w=64}` | 1 | 262,144 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=4,cout=4,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=16384,padding=0,stride=1,w=64}` | 1 | 65,536 | cpu | cpu | - |
| `groupnorm{channels=512,groups=32,hw=4096}` | 21 | 0 | cpu | cpu | - |
| `silu{numel=2097152}` | 19 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=2097152,operands=tensor}` | 11 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=2097152,operands=scalar}` | 11 | 0 | cpu | cpu | - |
| `silu{numel=33554432}` | 11 | 0 | cpu | cpu | - |
| `groupnorm{channels=128,groups=32,hw=262144}` | 10 | 0 | cpu | cpu | - |
| `silu{numel=8388608}` | 10 | 0 | cpu | cpu | - |
| `groupnorm{channels=512,groups=32,hw=16384}` | 9 | 0 | cpu | cpu | - |
| `groupnorm{channels=256,groups=32,hw=65536}` | 8 | 0 | cpu | cpu | - |
| `silu{numel=16777216}` | 8 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=16777216,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=33554432,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=8388608,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=16777216,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=33554432,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=8388608,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `exp{numel=16384}` | 2 | 0 | cpu | cpu | - |
| `clamp{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=128,groups=32,hw=65536}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=256,groups=32,hw=16384}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=256,groups=32,hw=262144}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=512,groups=32,hw=65536}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=16384,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `pad{numel=16908544}` | 1 | 0 | cpu | cpu | - |
| `pad{numel=33685632}` | 1 | 0 | cpu | cpu | - |
| `pad{numel=8520192}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=4194304}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=67108864}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=256,h=256,mode=nearest2d,out_elements=67108864,w=256}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=512,h=128,mode=nearest2d,out_elements=33554432,w=128}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=512,h=64,mode=nearest2d,out_elements=8388608,w=64}` | 1 | 0 | cpu | cpu | - |

