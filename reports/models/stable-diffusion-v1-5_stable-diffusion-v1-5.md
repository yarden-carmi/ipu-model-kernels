# stable-diffusion-v1-5/stable-diffusion-v1-5

- domain: diffusion, family: sd-unet, size: 860M, params at full depth: 859.5M
- canonical: stable-diffusion-v1-5/stable-diffusion-v1-5
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `attention{b=1,d=40,heads=8,kv=4096,q=4096}` | 5 | 10,737,418,240 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=327680,padding=1,stride=1,w=16}` | 7 | 3,774,873,600 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=320,cout=320,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=1310720,padding=1,stride=1,w=64}` | 7 | 3,774,873,600 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=655360,padding=1,stride=1,w=32}` | 6 | 3,774,873,600 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=256,n=10240}` | 5 | 3,355,443,200 | cpu | cpu | - |
| `linear{bias=1,k=320,m=4096,n=2560}` | 5 | 3,355,443,200 | cpu | cpu | - |
| `linear{bias=1,k=640,m=1024,n=5120}` | 5 | 3,355,443,200 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=1310720,padding=1,stride=1,w=32}` | 1 | 15,099,494,400 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=2560,cout=1280,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=327680,padding=1,stride=1,w=16}` | 2 | 7,549,747,200 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=320,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=1310720,padding=1,stride=1,w=64}` | 2 | 7,549,747,200 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=640,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=2621440,padding=1,stride=1,w=64}` | 1 | 15,099,494,400 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=1920,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=655360,padding=1,stride=1,w=32}` | 1 | 11,324,620,800 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=960,cout=320,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=1310720,padding=1,stride=1,w=64}` | 1 | 11,324,620,800 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=8,kh=3,kw=3,out_elements=81920,padding=1,stride=1,w=8}` | 11 | 943,718,400 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=0,k=1280,m=256,n=1280}` | 20 | 419,430,400 | cpu | cpu | - |
| `linear{bias=0,k=320,m=4096,n=320}` | 20 | 419,430,400 | cpu | cpu | - |
| `linear{bias=0,k=640,m=1024,n=640}` | 20 | 419,430,400 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=4096,n=320}` | 5 | 1,677,721,600 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=1024,n=640}` | 5 | 1,677,721,600 | cpu | cpu | - |
| `linear{bias=1,k=5120,m=256,n=1280}` | 5 | 1,677,721,600 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=655360,padding=1,stride=1,w=32}` | 1 | 7,549,747,200 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `attention{b=1,d=80,heads=8,kv=1024,q=1024}` | 5 | 1,342,177,280 | cpu | cpu | - |
| `conv2d{bias=1,cin=1920,cout=1280,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=327680,padding=1,stride=1,w=16}` | 1 | 5,662,310,400 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=2560,cout=1280,dilation=1,groups=1,h=8,kh=3,kw=3,out_elements=81920,padding=1,stride=1,w=8}` | 3 | 1,887,436,800 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=960,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=655360,padding=1,stride=1,w=32}` | 1 | 5,662,310,400 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=327680,padding=0,stride=1,w=16}` | 10 | 419,430,400 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=320,cout=320,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1310720,padding=0,stride=1,w=64}` | 10 | 419,430,400 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=640,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=655360,padding=0,stride=1,w=32}` | 10 | 419,430,400 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=256,n=1280}` | 10 | 419,430,400 | cpu | cpu | - |
| `linear{bias=1,k=320,m=4096,n=320}` | 10 | 419,430,400 | cpu | cpu | - |
| `linear{bias=1,k=640,m=1024,n=640}` | 10 | 419,430,400 | cpu | cpu | - |
| `conv2d{bias=1,cin=320,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=655360,padding=1,stride=1,w=32}` | 1 | 1,887,436,800 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=1280,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=327680,padding=1,stride=1,w=16}` | 1 | 1,887,436,800 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=2560,cout=1280,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=327680,padding=0,stride=1,w=16}` | 2 | 838,860,800 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=320,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1310720,padding=0,stride=1,w=64}` | 2 | 838,860,800 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=1920,cout=640,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=655360,padding=0,stride=1,w=32}` | 1 | 1,258,291,200 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=960,cout=320,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1310720,padding=0,stride=1,w=64}` | 1 | 1,258,291,200 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `attention{b=1,d=40,heads=8,kv=77,q=4096}` | 5 | 201,850,880 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=81920,padding=1,stride=2,w=16}` | 1 | 943,718,400 | cpu | cpu | - |
| `conv2d{bias=1,cin=320,cout=320,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=327680,padding=1,stride=2,w=64}` | 1 | 943,718,400 | cpu | cpu | - |
| `conv2d{bias=1,cin=640,cout=640,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=163840,padding=1,stride=2,w=32}` | 1 | 943,718,400 | cpu | cpu | - |
| `linear{bias=0,k=768,m=77,n=1280}` | 12 | 75,694,080 | cpu | cpu | - |
| `attention{b=1,d=160,heads=8,kv=256,q=256}` | 5 | 167,772,160 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=640,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=655360,padding=0,stride=1,w=32}` | 1 | 838,860,800 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=64,n=10240}` | 1 | 838,860,800 | cpu | cpu | - |
| `conv2d{bias=1,cin=1920,cout=1280,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=327680,padding=0,stride=1,w=16}` | 1 | 629,145,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=2560,cout=1280,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=81920,padding=0,stride=1,w=8}` | 3 | 209,715,200 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=960,cout=640,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=655360,padding=0,stride=1,w=32}` | 1 | 629,145,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `attention{b=1,d=80,heads=8,kv=77,q=1024}` | 5 | 100,925,440 | cpu | cpu | - |
| `linear{bias=0,k=1280,m=64,n=1280}` | 4 | 104,857,600 | cpu | cpu | - |
| `linear{bias=1,k=5120,m=64,n=1280}` | 1 | 419,430,400 | cpu | cpu | - |
| `linear{bias=0,k=768,m=77,n=640}` | 10 | 37,847,040 | cpu | cpu | - |
| `attention{b=1,d=160,heads=8,kv=77,q=256}` | 5 | 50,462,720 | cpu | cpu | - |
| `conv2d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=81920,padding=0,stride=1,w=8}` | 2 | 104,857,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=320,cout=640,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=655360,padding=0,stride=1,w=32}` | 1 | 209,715,200 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=640,cout=1280,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=327680,padding=0,stride=1,w=16}` | 1 | 209,715,200 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=64,n=1280}` | 2 | 104,857,600 | cpu | cpu | - |
| `linear{bias=0,k=768,m=77,n=320}` | 10 | 18,923,520 | cpu | cpu | - |
| `conv2d{bias=1,cin=320,cout=4,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=16384,padding=1,stride=1,w=64}` | 1 | 47,185,920 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=4,cout=320,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=1310720,padding=1,stride=1,w=64}` | 1 | 47,185,920 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=1,n=1280}` | 13 | 1,638,400 | cpu | cpu | - |
| `attention{b=1,d=160,heads=8,kv=77,q=64}` | 1 | 12,615,680 | cpu | cpu | - |
| `attention{b=1,d=160,heads=8,kv=64,q=64}` | 1 | 10,485,760 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=1,n=640}` | 5 | 819,200 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=1,n=320}` | 5 | 409,600 | cpu | cpu | - |
| `linear{bias=1,k=320,m=1,n=1280}` | 1 | 409,600 | cpu | cpu | - |
| `add{broadcast=0,numel=1310720,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=327680,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=655360,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `silu{numel=1280}` | 23 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `div{broadcast=0,numel=1310720,operands=scalar}` | 15 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=327680,operands=scalar}` | 15 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=655360,operands=scalar}` | 15 | 0 | cpu | cpu | - |
| `layernorm{channels=1280,layout=channels_last,tokens=256}` | 15 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `layernorm{channels=320,layout=channels_last,tokens=4096}` | 15 | 0 | cpu | cpu | - |
| `layernorm{channels=640,layout=channels_last,tokens=1024}` | 15 | 0 | cpu | cpu | - |
| `groupnorm{channels=320,groups=32,hw=4096}` | 13 | 0 | cpu | cpu | - |
| `groupnorm{channels=1280,groups=32,hw=64}` | 12 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=81920,operands=tensor}` | 11 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `groupnorm{channels=1280,groups=32,hw=256}` | 11 | 0 | cpu | cpu | - |
| `groupnorm{channels=640,groups=32,hw=1024}` | 11 | 0 | cpu | cpu | - |
| `silu{numel=81920}` | 11 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `div{broadcast=0,numel=81920,operands=scalar}` | 9 | 0 | cpu | cpu | - |
| `silu{numel=1310720}` | 9 | 0 | cpu | cpu | - |
| `silu{numel=655360}` | 8 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `add{broadcast=1,numel=81920,operands=tensor}` | 7 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `silu{numel=327680}` | 7 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `add{broadcast=1,numel=1310720,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=327680,operands=tensor}` | 5 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=655360,operands=tensor}` | 5 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu{numel=1310720}` | 5 | 0 | cpu | cpu | - |
| `gelu{numel=2621440}` | 5 | 0 | cpu | cpu | - |
| `gelu{numel=5242880}` | 5 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1310720,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2621440,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=5242880,operands=tensor}` | 5 | 0 | cpu | cpu | - |
| `silu{numel=163840}` | 4 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `concat{numel=163840}` | 3 | 0 | cpu | cpu | - |
| `groupnorm{channels=2560,groups=32,hw=64}` | 3 | 0 | cpu | cpu | - |
| `layernorm{channels=1280,layout=channels_last,tokens=64}` | 3 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `concat{numel=2621440}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=320}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=655360}` | 2 | 0 | cpu | cpu | - |
| `groupnorm{channels=2560,groups=32,hw=256}` | 2 | 0 | cpu | cpu | - |
| `groupnorm{channels=640,groups=32,hw=4096}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=160,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `silu{numel=2621440}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=1310720}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=1966080}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=3932160}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=491520}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=983040}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=160}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=160,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `exp{numel=160}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=327680}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=1280,groups=32,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=1920,groups=32,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=1920,groups=32,hw=256}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=320,groups=32,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=640,groups=32,hw=256}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=960,groups=32,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=960,groups=32,hw=4096}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=327680,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=160,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `silu{numel=1966080}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=3932160}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=491520}` | 1 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `silu{numel=983040}` | 1 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `sin{numel=160}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1280,h=16,mode=nearest2d,out_elements=1310720,w=16}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1280,h=8,mode=nearest2d,out_elements=327680,w=8}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=640,h=32,mode=nearest2d,out_elements=2621440,w=32}` | 1 | 0 | cpu | cpu | - |

