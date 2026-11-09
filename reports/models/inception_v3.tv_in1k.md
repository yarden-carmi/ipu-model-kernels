# inception_v3.tv_in1k

- domain: vision-cnn, family: inception, size: 23.8M, params at full depth: 23.8M
- canonical: inception_v3.tv_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=80,cout=192,dilation=1,groups=1,h=73,kh=3,kw=3,out_elements=967872,padding=0,stride=1,w=73}` | 1 | 696,867,840 | cpu | cpu | - |
| `conv2d{bias=0,cin=768,cout=192,dilation=1,groups=1,h=17,kh=1,kw=1,out_elements=55488,padding=0,stride=1,w=17}` | 12 | 42,614,784 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=32,cout=64,dilation=1,groups=1,h=147,kh=3,kw=3,out_elements=1382976,padding=1,stride=1,w=147}` | 1 | 398,297,088 | cpu | cpu | - |
| `conv2d{bias=0,cin=96,cout=96,dilation=1,groups=1,h=35,kh=3,kw=3,out_elements=117600,padding=1,stride=1,w=35}` | 3 | 101,606,400 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=192,dilation=1,groups=1,h=17,kh=1,kw=7,out_elements=55488,padding=0x3,stride=1,w=17}` | 4 | 74,575,872 | cpu | cpu | - |
| `conv2d{bias=0,cin=192,cout=192,dilation=1,groups=1,h=17,kh=7,kw=1,out_elements=55488,padding=3x0,stride=1,w=17}` | 4 | 74,575,872 | cpu | cpu | - |
| `conv2d{bias=0,cin=288,cout=384,dilation=1,groups=1,h=35,kh=3,kw=3,out_elements=110976,padding=0,stride=2,w=35}` | 1 | 287,649,792 | cpu | cpu | - |
| `conv2d{bias=0,cin=48,cout=64,dilation=1,groups=1,h=35,kh=5,kw=5,out_elements=78400,padding=2,stride=1,w=35}` | 3 | 94,080,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=96,dilation=1,groups=1,h=35,kh=3,kw=3,out_elements=117600,padding=1,stride=1,w=35}` | 4 | 67,737,600 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=160,dilation=1,groups=1,h=17,kh=1,kw=7,out_elements=46240,padding=0x3,stride=1,w=17}` | 4 | 51,788,800 | cpu | cpu | - |
| `conv2d{bias=0,cin=160,cout=160,dilation=1,groups=1,h=17,kh=7,kw=1,out_elements=46240,padding=3x0,stride=1,w=17}` | 4 | 51,788,800 | cpu | cpu | - |
| `conv2d{bias=0,cin=32,cout=32,dilation=1,groups=1,h=149,kh=3,kw=3,out_elements=691488,padding=0,stride=1,w=149}` | 1 | 199,148,544 | cpu | cpu | - |
| `conv2d{bias=0,cin=448,cout=384,dilation=1,groups=1,h=8,kh=3,kw=3,out_elements=24576,padding=1,stride=1,w=8}` | 2 | 99,090,432 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=768,cout=160,dilation=1,groups=1,h=17,kh=1,kw=1,out_elements=46240,padding=0,stride=1,w=17}` | 4 | 35,512,320 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=192,dilation=1,groups=1,h=17,kh=1,kw=7,out_elements=55488,padding=0x3,stride=1,w=17}` | 2 | 62,146,560 | cpu | cpu | - |
| `conv2d{bias=0,cin=160,cout=192,dilation=1,groups=1,h=17,kh=7,kw=1,out_elements=55488,padding=3x0,stride=1,w=17}` | 2 | 62,146,560 | cpu | cpu | - |
| `conv2d{bias=0,cin=384,cout=384,dilation=1,groups=1,h=8,kh=1,kw=3,out_elements=24576,padding=0x1,stride=1,w=8}` | 4 | 28,311,552 | cpu | cpu | - |
| `conv2d{bias=0,cin=384,cout=384,dilation=1,groups=1,h=8,kh=3,kw=1,out_elements=24576,padding=1x0,stride=1,w=8}` | 4 | 28,311,552 | cpu | cpu | - |
| `conv2d{bias=0,cin=288,cout=64,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=78400,padding=0,stride=1,w=35}` | 4 | 22,579,200 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=17,kh=1,kw=7,out_elements=36992,padding=0x3,stride=1,w=17}` | 2 | 33,144,832 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=17,kh=7,kw=1,out_elements=36992,padding=3x0,stride=1,w=17}` | 2 | 33,144,832 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=64,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=78400,padding=0,stride=1,w=35}` | 3 | 20,070,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=2048,cout=448,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=28672,padding=0,stride=1,w=8}` | 1 | 58,720,256 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=768,cout=128,dilation=1,groups=1,h=17,kh=1,kw=1,out_elements=36992,padding=0,stride=1,w=17}` | 2 | 28,409,856 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=2048,cout=384,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=24576,padding=0,stride=1,w=8}` | 1 | 50,331,648 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=192,dilation=1,groups=1,h=17,kh=1,kw=7,out_elements=55488,padding=0x3,stride=1,w=17}` | 1 | 49,717,248 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=192,dilation=1,groups=1,h=17,kh=7,kw=1,out_elements=55488,padding=3x0,stride=1,w=17}` | 1 | 49,717,248 | cpu | cpu | - |
| `conv2d{bias=0,cin=2048,cout=320,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=20480,padding=0,stride=1,w=8}` | 1 | 41,943,040 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1280,cout=448,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=28672,padding=0,stride=1,w=8}` | 1 | 36,700,160 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=320,dilation=1,groups=1,h=17,kh=3,kw=3,out_elements=20480,padding=0,stride=2,w=17}` | 1 | 35,389,440 | cpu | cpu | - |
| `conv2d{bias=0,cin=1280,cout=384,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=24576,padding=0,stride=1,w=8}` | 1 | 31,457,280 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=64,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=78400,padding=0,stride=1,w=35}` | 2 | 15,052,800 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=80,dilation=1,groups=1,h=73,kh=1,kw=1,out_elements=426320,padding=0,stride=1,w=73}` | 1 | 27,284,480 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1280,cout=320,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=20480,padding=0,stride=1,w=8}` | 1 | 26,214,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=2048,cout=192,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=12288,padding=0,stride=1,w=8}` | 1 | 25,165,824 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=96,dilation=1,groups=1,h=35,kh=3,kw=3,out_elements=27744,padding=0,stride=2,w=35}` | 1 | 23,970,816 | cpu | cpu | - |
| `conv2d{bias=0,cin=192,cout=192,dilation=1,groups=1,h=17,kh=3,kw=3,out_elements=12288,padding=0,stride=2,w=17}` | 1 | 21,233,664 | cpu | cpu | - |
| `conv2d{bias=0,cin=3,cout=32,dilation=1,groups=1,h=299,kh=3,kw=3,out_elements=710432,padding=0,stride=2,w=299}` | 1 | 19,181,664 | cpu | cpu | - |
| `conv2d{bias=0,cin=288,cout=48,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=58800,padding=0,stride=1,w=35}` | 1 | 16,934,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1280,cout=192,dilation=1,groups=1,h=8,kh=1,kw=1,out_elements=12288,padding=0,stride=1,w=8}` | 1 | 15,728,640 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=48,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=58800,padding=0,stride=1,w=35}` | 1 | 15,052,800 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=48,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=58800,padding=0,stride=1,w=35}` | 1 | 11,289,600 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=32,dilation=1,groups=1,h=35,kh=1,kw=1,out_elements=39200,padding=0,stride=1,w=35}` | 1 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=2048,m=1,n=1000}` | 1 | 2,048,000 | cpu | cpu | - |
| `batchnorm{channels=192,hw=289}` | 26 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=289}` | 12 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=64}` | 12 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=1225}` | 12 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=1225}` | 7 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=289}` | 6 | 0 | cpu | cpu | - |
| `concat{numel=221952}` | 5 | 0 | cpu | cpu | - |
| `avgpool2d{channels=768,h=17,k=3,padding=1,stride=1,w=17}` | 4 | 0 | cpu | cpu | - |
| `concat{numel=49152}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=64}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=64}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=48,hw=1225}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=448,hw=64}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=131072}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=352800}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=2048,h=8,out=1,w=8}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=2048,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=1280,h=8,k=3,padding=1,stride=1,w=8}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=192,h=35,k=3,padding=1,stride=1,w=35}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=2048,h=8,k=3,padding=1,stride=1,w=8}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=256,h=35,k=3,padding=1,stride=1,w=35}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=288,h=35,k=3,padding=1,stride=1,w=35}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=5041}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=1225}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=21609}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=22201}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=289}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=21609}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=80,hw=5329}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=289}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=313600}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=81920}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=192,h=71,k=3,padding=0,stride=2,w=71}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=288,h=35,k=3,padding=0,stride=2,w=35}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=64,h=147,k=3,padding=0,stride=2,w=147}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=768,h=17,k=3,padding=0,stride=2,w=17}` | 1 | 0 | cpu | cpu | - |

