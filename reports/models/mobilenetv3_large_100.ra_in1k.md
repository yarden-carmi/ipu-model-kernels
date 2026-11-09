# mobilenetv3_large_100.ra_in1k

- domain: vision-cnn, family: mobilenetv3, size: 5.5M, params at full depth: 5.5M
- canonical: mobilenetv3_large_100.ra_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=112,cout=672,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=131712,padding=0,stride=1,w=14}` | 2 | 14,751,744 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=960,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=47040,padding=0,stride=1,w=7}` | 3 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=160,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=7840,padding=0,stride=1,w=7}` | 2 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=112,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=21952,padding=0,stride=1,w=14}` | 1 | 14,751,744 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=64,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=802816,padding=0,stride=1,w=112}` | 1 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=24,cout=72,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=225792,padding=0,stride=1,w=56}` | 2 | 5,419,008 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=480,cout=112,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=21952,padding=0,stride=1,w=14}` | 1 | 10,536,960 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=120,cout=40,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=31360,padding=0,stride=1,w=28}` | 2 | 3,763,200 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=40,cout=120,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=94080,padding=0,stride=1,w=28}` | 2 | 3,763,200 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=40,cout=240,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=188160,padding=0,stride=1,w=28}` | 1 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=80,cout=480,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=94080,padding=0,stride=1,w=14}` | 1 | 7,526,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=184,cout=80,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=14}` | 2 | 2,885,120 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=80,cout=184,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=36064,padding=0,stride=1,w=14}` | 2 | 2,885,120 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=16,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=200704,padding=1,stride=2,w=224}` | 1 | 5,419,008 | cpu | cpu | - |
| `conv2d{bias=0,cin=72,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 5,419,008 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=160,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=7840,padding=0,stride=1,w=7}` | 1 | 5,268,480 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=24,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=75264,padding=0,stride=1,w=56}` | 1 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=120,cout=120,dilation=1,groups=120,h=28,kh=5,kw=5,out_elements=94080,padding=2,stride=1,w=28}` | 2 | 2,352,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=240,cout=80,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=14}` | 1 | 3,763,200 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=16,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=112}` | 1 | 3,211,264 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=200,cout=80,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=15680,padding=0,stride=1,w=14}` | 1 | 3,136,000 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=80,cout=200,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=39200,padding=0,stride=1,w=14}` | 1 | 3,136,000 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=960,dilation=1,groups=960,h=7,kh=5,kw=5,out_elements=47040,padding=2,stride=1,w=7}` | 2 | 1,176,000 | cpu | cpu | - |
| `conv2d{bias=0,cin=72,cout=40,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=31360,padding=0,stride=1,w=28}` | 1 | 2,257,920 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=72,cout=72,dilation=1,groups=72,h=56,kh=3,kw=3,out_elements=225792,padding=1,stride=1,w=56}` | 1 | 2,032,128 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=16,cout=16,dilation=1,groups=16,h=112,kh=3,kw=3,out_elements=200704,padding=1,stride=1,w=112}` | 1 | 1,806,336 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=64,h=112,kh=3,kw=3,out_elements=200704,padding=1,stride=2,w=112}` | 1 | 1,806,336 | cpu | cpu | - |
| `conv2d{bias=0,cin=72,cout=72,dilation=1,groups=72,h=56,kh=5,kw=5,out_elements=56448,padding=2,stride=2,w=56}` | 1 | 1,411,200 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=1,n=1000}` | 1 | 1,280,000 | cpu | cpu | - |
| `conv2d{bias=1,cin=960,cout=1280,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=1280,padding=0,stride=1,w=1}` | 1 | 1,228,800 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=672,dilation=1,groups=672,h=14,kh=3,kw=3,out_elements=131712,padding=1,stride=1,w=14}` | 1 | 1,185,408 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=480,cout=480,dilation=1,groups=480,h=14,kh=3,kw=3,out_elements=94080,padding=1,stride=1,w=14}` | 1 | 846,720 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=672,dilation=1,groups=672,h=14,kh=5,kw=5,out_elements=32928,padding=2,stride=2,w=14}` | 1 | 823,200 | cpu | cpu | - |
| `conv2d{bias=0,cin=184,cout=184,dilation=1,groups=184,h=14,kh=3,kw=3,out_elements=36064,padding=1,stride=1,w=14}` | 2 | 324,576 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=240,cout=960,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=960,padding=0,stride=1,w=1}` | 2 | 230,400 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=960,cout=240,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=240,padding=0,stride=1,w=1}` | 2 | 230,400 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=240,cout=240,dilation=1,groups=240,h=28,kh=3,kw=3,out_elements=47040,padding=1,stride=2,w=28}` | 1 | 423,360 | cpu | cpu | - |
| `conv2d{bias=0,cin=200,cout=200,dilation=1,groups=200,h=14,kh=3,kw=3,out_elements=39200,padding=1,stride=1,w=14}` | 1 | 352,800 | chip-emu | chip-emu | depthwise_conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=168,cout=672,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=672,padding=0,stride=1,w=1}` | 2 | 112,896 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=672,cout=168,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=168,padding=0,stride=1,w=1}` | 2 | 112,896 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=120,cout=480,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=480,padding=0,stride=1,w=1}` | 1 | 57,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=480,cout=120,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=120,padding=0,stride=1,w=1}` | 1 | 57,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=120,cout=32,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=32,padding=0,stride=1,w=1}` | 2 | 3,840 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=32,cout=120,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=120,padding=0,stride=1,w=1}` | 2 | 3,840 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=24,cout=72,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=72,padding=0,stride=1,w=1}` | 1 | 1,728 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=72,cout=24,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=24,padding=0,stride=1,w=1}` | 1 | 1,728 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=960,hw=49}` | 5 | 0 | cpu | cpu | - |
| `batchnorm{channels=120,hw=784}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=184,hw=196}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=80,hw=196}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=15680,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=16,hw=12544}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=49}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=40,hw=784}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=196}` | 3 | 0 | cpu | cpu | - |
| `batchnorm{channels=72,hw=3136}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=94080,operands=tensor}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=31360,operands=tensor}` | 2 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=7840,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=112,hw=196}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=200,hw=196}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=24,hw=3136}` | 2 | 0 | cpu | cpu | - |
| `batchnorm{channels=480,hw=196}` | 2 | 0 | cpu | cpu | - |
| `hardsigmoid{numel=120}` | 2 | 0 | cpu | cpu | - |
| `hardsigmoid{numel=672}` | 2 | 0 | cpu | cpu | - |
| `hardsigmoid{numel=960}` | 2 | 0 | cpu | cpu | - |
| `mean{numel=47040,out=960}` | 2 | 0 | cpu | cpu | - |
| `mean{numel=94080,out=120}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=47040,operands=tensor}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=168}` | 2 | 0 | cpu | cpu | - |
| `relu{numel=240}` | 2 | 0 | cpu | cpu | - |
| `relu{numel=32}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=960,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=200704,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=21952,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=75264,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=1280,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=240,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=240,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=72,hw=784}` | 1 | 0 | cpu | cpu | - |
| `hardsigmoid{numel=480}` | 1 | 0 | cpu | cpu | - |
| `hardsigmoid{numel=72}` | 1 | 0 | cpu | cpu | - |
| `hardswish{numel=1280}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=131712,out=672}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=32928,out=672}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=56448,out=72}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=94080,out=480}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=131712,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=32928,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=56448,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=120}` | 1 | 0 | cpu | cpu | - |
| `relu{numel=24}` | 1 | 0 | cpu | cpu | - |

