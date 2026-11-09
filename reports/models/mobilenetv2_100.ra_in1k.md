# mobilenetv2_100.ra_in1k

- domain: vision-cnn, family: mobilenetv2, size: 3.5M, params at full depth: 3.5M
- canonical: mobilenetv2_100.ra_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=96,cout=576,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=112896,padding=0,stride=1,w=14}` | 3 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=960,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=47040,padding=0,stride=1,w=7}` | 3 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=24,cout=144,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=451584,padding=0,stride=1,w=56}` | 2 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=576,cout=96,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=18816,padding=0,stride=1,w=14}` | 2 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=1280,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=62720,padding=0,stride=1,w=7}` | 1 | 20,070,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=96,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=1204224,padding=0,stride=1,w=112}` | 1 | 19,267,584 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=384,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=14}` | 4 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=160,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=7840,padding=0,stride=1,w=7}` | 2 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=320,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=7}` | 1 | 15,052,800 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=32,cout=192,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=150528,padding=0,stride=1,w=28}` | 3 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=64,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=12544,padding=0,stride=1,w=14}` | 3 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 10,838,016 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=32,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=401408,padding=1,stride=2,w=224}` | 1 | 10,838,016 | cpu | cpu | - |
| `conv2d{bias=0,cin=192,cout=32,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=28}` | 2 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=96,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=18816,padding=0,stride=1,w=14}` | 1 | 7,225,344 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 7,225,344 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=32,cout=16,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=112}` | 1 | 6,422,528 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=576,cout=160,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=7840,padding=0,stride=1,w=7}` | 1 | 4,515,840 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=144,dilation=1,groups=144,h=56,kh=3,kw=3,out_elements=451584,padding=1,stride=1,w=56}` | 1 | 4,064,256 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=32,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=28}` | 1 | 3,612,672 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=32,cout=32,dilation=1,groups=32,h=112,kh=3,kw=3,out_elements=401408,padding=1,stride=1,w=112}` | 1 | 3,612,672 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=192,dilation=1,groups=192,h=28,kh=3,kw=3,out_elements=150528,padding=1,stride=1,w=28}` | 2 | 1,354,752 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=384,dilation=1,groups=384,h=14,kh=3,kw=3,out_elements=75264,padding=1,stride=1,w=14}` | 4 | 677,376 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=96,dilation=1,groups=96,h=112,kh=3,kw=3,out_elements=301056,padding=1,stride=2,w=112}` | 1 | 2,709,504 | cpu | cpu | - |
| `conv2d{bias=0,cin=192,cout=64,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=12544,padding=0,stride=1,w=14}` | 1 | 2,408,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=576,cout=576,dilation=1,groups=576,h=14,kh=3,kw=3,out_elements=112896,padding=1,stride=1,w=14}` | 2 | 1,016,064 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1280,m=1,n=1000}` | 1 | 1,280,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=960,cout=960,dilation=1,groups=960,h=7,kh=3,kw=3,out_elements=47040,padding=1,stride=1,w=7}` | 3 | 423,360 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=144,cout=144,dilation=1,groups=144,h=56,kh=3,kw=3,out_elements=112896,padding=1,stride=2,w=56}` | 1 | 1,016,064 | cpu | cpu | - |
| `conv2d{bias=0,cin=192,cout=192,dilation=1,groups=192,h=28,kh=3,kw=3,out_elements=37632,padding=1,stride=2,w=28}` | 1 | 338,688 | cpu | cpu | - |
| `conv2d{bias=0,cin=576,cout=576,dilation=1,groups=576,h=14,kh=3,kw=3,out_elements=28224,padding=1,stride=2,w=14}` | 1 | 254,016 | cpu | cpu | - |
| `batchnorm{channels=384,hw=196}` | 8 | 0 | cpu | cpu | - |
| `batchnorm{channels=960,hw=49}` | 6 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=784}` | 5 | 0 | cpu | cpu | - |
| `batchnorm{channels=576,hw=196}` | 5 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=196}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=12544,operands=tensor}` | 3 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=144,hw=3136}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=49}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=784}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=196}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=18816,operands=tensor}` | 2 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=25088,operands=tensor}` | 2 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=7840,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=24,hw=3136}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=12544}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=1280,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=75264,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=1280,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=1280,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=144,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=16,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=576,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=3136}` | 1 | 0 | cpu | cpu | - |

