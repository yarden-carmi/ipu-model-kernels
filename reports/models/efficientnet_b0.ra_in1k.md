# efficientnet_b0.ra_in1k

- domain: vision-cnn, family: efficientnet, size: 5.3M, params at full depth: 5.3M
- canonical: efficientnet_b0.ra_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=112,cout=672,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=131712,padding=0,stride=1,w=14}` | 3 | 14,751,744 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=1152,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=56448,padding=0,stride=1,w=7}` | 4 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1152,cout=192,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=9408,padding=0,stride=1,w=7}` | 3 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=112,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=21952,padding=0,stride=1,w=14}` | 2 | 14,751,744 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=80,cout=480,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=94080,padding=0,stride=1,w=14}` | 3 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=24,cout=144,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=451584,padding=0,stride=1,w=56}` | 2 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=1280,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=62720,padding=0,stride=1,w=7}` | 1 | 20,070,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=96,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=1204224,padding=0,stride=1,w=112}` | 1 | 19,267,584 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1152,cout=320,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=7}` | 1 | 18,063,360 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=40,cout=240,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=188160,padding=0,stride=1,w=28}` | 2 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=480,cout=80,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=14}` | 2 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=32,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=401408,padding=1,stride=2,w=224}` | 1 | 10,838,016 | cpu | cpu | - |
| `conv2d{bias=0,cin=480,cout=112,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=21952,padding=0,stride=1,w=14}` | 1 | 10,536,960 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=40,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=31360,padding=0,stride=1,w=28}` | 1 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 7,225,344 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=672,dilation=1,groups=672,h=14,kh=5,kw=5,out_elements=131712,padding=2,stride=1,w=14}` | 2 | 3,292,800 | cpu | cpu | - |
| `conv2d{bias=0,cin=32,cout=16,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=112}` | 1 | 6,422,528 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=192,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=9408,padding=0,stride=1,w=7}` | 1 | 6,322,176 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=240,dilation=1,groups=240,h=28,kh=5,kw=5,out_elements=188160,padding=2,stride=1,w=28}` | 1 | 4,704,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=144,cout=40,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=31360,padding=0,stride=1,w=28}` | 1 | 4,515,840 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1152,cout=1152,dilation=1,groups=1152,h=7,kh=5,kw=5,out_elements=56448,padding=2,stride=1,w=7}` | 3 | 1,411,200 | cpu | cpu | - |
| `conv2d{bias=0,cin=144,cout=144,dilation=1,groups=144,h=56,kh=3,kw=3,out_elements=451584,padding=1,stride=1,w=56}` | 1 | 4,064,256 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=80,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=14}` | 1 | 3,763,200 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=32,cout=32,dilation=1,groups=32,h=112,kh=3,kw=3,out_elements=401408,padding=1,stride=1,w=112}` | 1 | 3,612,672 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=144,dilation=1,groups=144,h=56,kh=5,kw=5,out_elements=112896,padding=2,stride=2,w=56}` | 1 | 2,822,400 | cpu | cpu | - |
| `conv2d{bias=0,cin=96,cout=96,dilation=1,groups=96,h=112,kh=3,kw=3,out_elements=301056,padding=1,stride=2,w=112}` | 1 | 2,709,504 | cpu | cpu | - |
| `conv2d{bias=0,cin=480,cout=480,dilation=1,groups=480,h=14,kh=5,kw=5,out_elements=94080,padding=2,stride=1,w=14}` | 1 | 2,352,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=480,cout=480,dilation=1,groups=480,h=14,kh=3,kw=3,out_elements=94080,padding=1,stride=1,w=14}` | 2 | 846,720 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=1,n=1000}` | 1 | 1,280,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=672,cout=672,dilation=1,groups=672,h=14,kh=5,kw=5,out_elements=32928,padding=2,stride=2,w=14}` | 1 | 823,200 | cpu | cpu | - |
| `conv2d{bias=0,cin=1152,cout=1152,dilation=1,groups=1152,h=7,kh=3,kw=3,out_elements=56448,padding=1,stride=1,w=7}` | 1 | 508,032 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=240,dilation=1,groups=240,h=28,kh=3,kw=3,out_elements=47040,padding=1,stride=2,w=28}` | 1 | 423,360 | cpu | cpu | - |
| `conv2d{bias=1,cin=1152,cout=48,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=48,padding=0,stride=1,w=1}` | 4 | 55,296 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=48,cout=1152,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=1152,padding=0,stride=1,w=1}` | 4 | 55,296 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=28,cout=672,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=672,padding=0,stride=1,w=1}` | 3 | 18,816 | cpu | cpu | - |
| `conv2d{bias=1,cin=672,cout=28,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=28,padding=0,stride=1,w=1}` | 3 | 18,816 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=20,cout=480,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=480,padding=0,stride=1,w=1}` | 3 | 9,600 | cpu | cpu | - |
| `conv2d{bias=1,cin=480,cout=20,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=20,padding=0,stride=1,w=1}` | 3 | 9,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=10,cout=240,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=240,padding=0,stride=1,w=1}` | 2 | 2,400 | cpu | cpu | - |
| `conv2d{bias=1,cin=240,cout=10,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=10,padding=0,stride=1,w=1}` | 2 | 2,400 | cpu | cpu | - |
| `conv2d{bias=1,cin=144,cout=6,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=6,padding=0,stride=1,w=1}` | 2 | 864 | cpu | cpu | - |
| `conv2d{bias=1,cin=6,cout=144,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=144,padding=0,stride=1,w=1}` | 2 | 864 | cpu | cpu | - |
| `conv2d{bias=1,cin=4,cout=96,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=96,padding=0,stride=1,w=1}` | 1 | 384 | cpu | cpu | - |
| `conv2d{bias=1,cin=96,cout=4,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=4,padding=0,stride=1,w=1}` | 1 | 384 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=32,cout=8,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=8,padding=0,stride=1,w=1}` | 1 | 256 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=8,cout=32,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=32,padding=0,stride=1,w=1}` | 1 | 256 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=1152,hw=49}` | 8 | 0 | cpu | cpu | - |
| `batchnorm{channels=480,hw=196}` | 6 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=196}` | 5 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=49}` | 4 | 0 | cpu | cpu | - |
| `mean{numel=56448,out=1152}` | 4 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=56448,operands=tensor}` | 4 | 0 | cpu | cpu | - |
| `sigmoid{numel=1152}` | 4 | 0 | cpu | cpu | - |
| `silu{numel=48}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=9408,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=112,hw=196}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=144,hw=3136}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=240,hw=784}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=80,hw=196}` | 3 | 0 | cpu | cpu | - |
| `mean{numel=94080,out=480}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=94080,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `sigmoid{numel=480}` | 3 | 0 | cpu | cpu | - |
| `sigmoid{numel=672}` | 3 | 0 | cpu | cpu | - |
| `silu{numel=20}` | 3 | 0 | cpu | cpu | - |
| `silu{numel=28}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=15680,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=21952,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=24,hw=3136}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=12544}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=40,hw=784}` | 2 | 0 | cpu | cpu | - |
| `mean{numel=131712,out=672}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=131712,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `sigmoid{numel=144}` | 2 | 0 | cpu | cpu | - |
| `sigmoid{numel=240}` | 2 | 0 | cpu | cpu | - |
| `silu{numel=10}` | 2 | 0 | cpu | cpu | - |
| `silu{numel=6}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=1280,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=31360,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=75264,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=1280,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=1280,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=144,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=16,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=240,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=112896,out=144}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=188160,out=240}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=301056,out=96}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=32928,out=672}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=401408,out=32}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=451584,out=144}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=47040,out=240}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=112896,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=188160,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=301056,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32928,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=401408,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=451584,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=47040,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `sigmoid{numel=32}` | 1 | 0 | cpu | cpu | - |
| `sigmoid{numel=96}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=4}` | 1 | 0 | cpu | cpu | - |
| `silu{numel=8}` | 1 | 0 | cpu | cpu | - |

