# resnet50.a1_in1k

- domain: vision-cnn, family: resnet, size: 25.6M, params at full depth: 25.6M
- canonical: resnet50.a1_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=1,h=14,kh=3,kw=3,out_elements=50176,padding=1,stride=1,w=14}` | 5 | 115,605,504 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=100352,padding=1,stride=1,w=28}` | 3 | 115,605,504 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=200704,padding=1,stride=1,w=56}` | 3 | 115,605,504 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=1024,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=14}` | 6 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1024,cout=256,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=50176,padding=0,stride=1,w=14}` | 5 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=512,dilation=1,groups=1,h=7,kh=3,kw=3,out_elements=25088,padding=1,stride=1,w=7}` | 2 | 115,605,504 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=512,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=28}` | 4 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=256,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=802816,padding=0,stride=1,w=56}` | 4 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 3 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=2048,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=7}` | 3 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=64,dilation=1,groups=1,h=224,kh=7,kw=7,out_elements=802816,padding=3,stride=2,w=224}` | 1 | 118,013,952 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=100352,padding=1,stride=2,w=56}` | 1 | 115,605,504 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=50176,padding=1,stride=2,w=28}` | 1 | 115,605,504 | cpu | cpu | - |
| `conv2d{bias=0,cin=512,cout=512,dilation=1,groups=1,h=14,kh=3,kw=3,out_elements=25088,padding=1,stride=2,w=14}` | 1 | 115,605,504 | cpu | cpu | - |
| `conv2d{bias=0,cin=1024,cout=2048,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=100352,padding=0,stride=2,w=14}` | 1 | 102,760,448 | cpu | cpu | - |
| `conv2d{bias=0,cin=1024,cout=512,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=14}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=2048,cout=512,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=7}` | 2 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=512,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=2,w=56}` | 1 | 102,760,448 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=64,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=56}` | 2 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=1024,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=200704,padding=0,stride=2,w=28}` | 1 | 102,760,448 | cpu | cpu | - |
| `conv2d{bias=0,cin=512,cout=256,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=28}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=56}` | 1 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=2048,m=1,n=1000}` | 1 | 2,048,000 | cpu | cpu | - |
| `relu{numel=200704}` | 13 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=196}` | 11 | 0 | cpu | cpu | - |
| `relu{numel=100352}` | 11 | 0 | cpu | cpu | - |
| `relu{numel=50176}` | 11 | 0 | cpu | cpu | - |
| `batchnorm{channels=1024,hw=196}` | 7 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=784}` | 7 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=200704,operands=tensor}` | 6 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `batchnorm{channels=64,hw=3136}` | 6 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=49}` | 5 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=784}` | 5 | 0 | cpu | cpu | - |
| `relu{numel=25088}` | 5 | 0 | cpu | cpu | - |
| `relu{numel=401408}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=401408,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `batchnorm{channels=2048,hw=49}` | 4 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=3136}` | 4 | 0 | cpu | cpu | - |
| `relu{numel=802816}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=100352,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=802816,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=2048,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=2048,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=64,h=112,k=3,padding=1,stride=2,w=112}` | 1 | 0 | cpu | cpu | - |

