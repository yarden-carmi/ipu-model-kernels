# mobilevit_s.cvnets_in1k

- domain: vision-transformer, family: mobilevit, size: 5.6M, params at full depth: 5.6M
- canonical: mobilevit_s.cvnets_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=64,cout=256,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=64}` | 3 | 67,108,864 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=96,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=98304,padding=1,stride=1,w=32}` | 1 | 169,869,312 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `attention{b=4,d=36,heads=4,kv=256,q=256}` | 2 | 75,497,472 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=64,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=262144,padding=0,stride=1,w=64}` | 2 | 67,108,864 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=144,m=1024,n=432}` | 2 | 63,700,992 | cpu | cpu | - |
| `linear{bias=1,k=192,m=256,n=576}` | 4 | 28,311,552 | cpu | cpu | - |
| `conv2d{bias=0,cin=96,cout=96,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=98304,padding=1,stride=1,w=32}` | 1 | 84,934,656 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=144,m=1024,n=288}` | 2 | 42,467,328 | cpu | cpu | - |
| `linear{bias=1,k=288,m=1024,n=144}` | 2 | 42,467,328 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=32768,padding=1,stride=1,w=16}` | 1 | 75,497,472 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=192,m=256,n=384}` | 4 | 18,874,368 | cpu | cpu | - |
| `linear{bias=1,k=384,m=256,n=192}` | 4 | 18,874,368 | cpu | cpu | - |
| `conv2d{bias=0,cin=32,cout=128,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=2097152,padding=0,stride=1,w=128}` | 1 | 67,108,864 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=144,m=1024,n=144}` | 2 | 21,233,664 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=32768,padding=1,stride=1,w=16}` | 1 | 37,748,736 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=384,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=393216,padding=0,stride=1,w=32}` | 1 | 37,748,736 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=192,m=256,n=192}` | 4 | 9,437,184 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=64,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=262144,padding=0,stride=1,w=64}` | 1 | 33,554,432 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=32,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=524288,padding=0,stride=1,w=128}` | 1 | 33,554,432 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=240,m=64,n=720}` | 3 | 11,059,200 | cpu | cpu | - |
| `conv2d{bias=0,cin=320,cout=160,dilation=1,groups=1,h=8,kh=3,kw=3,out_elements=10240,padding=1,stride=1,w=8}` | 1 | 29,491,200 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `attention{b=4,d=48,heads=4,kv=64,q=64}` | 4 | 6,291,456 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=96,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=98304,padding=0,stride=1,w=32}` | 1 | 25,165,824 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=240,m=64,n=480}` | 3 | 7,372,800 | cpu | cpu | - |
| `linear{bias=1,k=480,m=64,n=240}` | 3 | 7,372,800 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=256,h=64,kh=3,kw=3,out_elements=1048576,padding=1,stride=1,w=64}` | 2 | 9,437,184 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=512,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=131072,padding=0,stride=1,w=16}` | 1 | 16,777,216 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=64,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=128}` | 1 | 16,777,216 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=160,dilation=1,groups=1,h=8,kh=3,kw=3,out_elements=10240,padding=1,stride=1,w=8}` | 1 | 14,745,600 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=96,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=98304,padding=0,stride=1,w=32}` | 1 | 14,155,776 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=144,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=147456,padding=0,stride=1,w=32}` | 1 | 14,155,776 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=128,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=32768,padding=0,stride=1,w=16}` | 1 | 12,582,912 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=240,m=64,n=240}` | 3 | 3,686,400 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=64,h=128,kh=3,kw=3,out_elements=1048576,padding=1,stride=1,w=128}` | 1 | 9,437,184 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=16,dilation=1,groups=1,h=256,kh=3,kw=3,out_elements=262144,padding=1,stride=2,w=256}` | 1 | 7,077,888 | cpu | cpu | - |
| `conv2d{bias=0,cin=160,cout=640,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=40960,padding=0,stride=1,w=8}` | 1 | 6,553,600 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=192,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=49152,padding=0,stride=1,w=16}` | 1 | 6,291,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=128,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=32768,padding=0,stride=1,w=16}` | 1 | 6,291,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=160,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=10240,padding=0,stride=1,w=8}` | 1 | 5,242,880 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=128,h=128,kh=3,kw=3,out_elements=524288,padding=1,stride=2,w=128}` | 1 | 4,718,592 | chip-emu | chip-emu | depthwise_conv_stride2_128 (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=240,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=15360,padding=0,stride=1,w=8}` | 1 | 2,457,600 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=160,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=10240,padding=0,stride=1,w=8}` | 1 | 2,457,600 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=256,h=64,kh=3,kw=3,out_elements=262144,padding=1,stride=2,w=64}` | 1 | 2,359,296 | chip-emu | chip-emu | depthwise_conv_stride2_narrow (chip-emu, exact, fp32-exact) |
| `attention{b=4,d=60,heads=4,kv=16,q=16}` | 3 | 491,520 | cpu | cpu | - |
| `conv2d{bias=0,cin=384,cout=384,dilation=1,groups=384,h=32,kh=3,kw=3,out_elements=98304,padding=1,stride=2,w=32}` | 1 | 884,736 | chip-emu | chip-emu | depthwise_conv_stride2_narrow (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=640,m=1,n=1000}` | 1 | 640,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=512,cout=512,dilation=1,groups=512,h=16,kh=3,kw=3,out_elements=32768,padding=1,stride=2,w=16}` | 1 | 294,912 | chip-emu | chip-emu | depthwise_conv_stride2_16 (chip-emu, exact, fp32-exact) |
| `layernorm{channels=192,layout=channels_last,tokens=256}` | 9 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=49152,operands=tensor}` | 8 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=240,layout=channels_last,tokens=64}` | 7 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=15360,operands=tensor}` | 6 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=256,hw=4096}` | 5 | 0 | cpu | cpu | - |
| `layernorm{channels=144,layout=channels_last,tokens=1024}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=147456,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `batchnorm{channels=128,hw=256}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=64}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=1024}` | 4 | 0 | cpu | cpu | - |
| `silu{numel=98304}` | 4 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `batchnorm{channels=64,hw=4096}` | 3 | 0 | cpu | cpu | - |
| `silu{numel=30720}` | 3 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `add{broadcast=0,numel=262144,operands=tensor}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `batchnorm{channels=64,hw=16384}` | 2 | 0 | cpu | cpu | - |
| `silu{numel=294912}` | 2 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `adaptive_avgpool2d{channels=640,h=8,out=1,w=8}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=640,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=16384}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=4096}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=16,hw=16384}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=16384}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=1024}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=256}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=256}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=64}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=640,hw=64}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=196608}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=20480}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=65536}` | 1 | 0 | cpu | cpu | - |

