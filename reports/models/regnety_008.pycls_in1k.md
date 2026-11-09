# regnety_008.pycls_in1k

- domain: vision-cnn, family: regnet, size: 6.3M, params at full depth: 6.3M
- canonical: regnety_008.pycls_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=320,cout=320,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=62720,padding=0,stride=1,w=14}` | 15 | 20,070,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=768,cout=768,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=37632,padding=0,stride=1,w=7}` | 3 | 28,901,376 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 5 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=320,dilation=1,groups=20,h=14,kh=3,kw=3,out_elements=62720,padding=1,stride=1,w=14}` | 7 | 9,031,680 | cpu | cpu | - |
| `conv2d{bias=0,cin=320,cout=768,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=150528,padding=0,stride=1,w=14}` | 1 | 48,168,960 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=320,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=250880,padding=0,stride=1,w=28}` | 1 | 32,112,640 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=8,h=28,kh=3,kw=3,out_elements=100352,padding=1,stride=1,w=28}` | 2 | 14,450,688 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=4,h=112,kh=3,kw=3,out_elements=200704,padding=1,stride=2,w=112}` | 1 | 28,901,376 | cpu | cpu | - |
| `conv2d{bias=0,cin=32,cout=64,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=802816,padding=0,stride=1,w=112}` | 1 | 25,690,112 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 25,690,112 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=8,h=56,kh=3,kw=3,out_elements=100352,padding=1,stride=2,w=56}` | 1 | 14,450,688 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=56}` | 1 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=768,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=37632,padding=0,stride=2,w=14}` | 1 | 12,042,240 | cpu | cpu | - |
| `conv2d{bias=0,cin=3,cout=32,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=401408,padding=1,stride=2,w=224}` | 1 | 10,838,016 | cpu | cpu | - |
| `conv2d{bias=0,cin=320,cout=320,dilation=1,groups=20,h=28,kh=3,kw=3,out_elements=62720,padding=1,stride=2,w=28}` | 1 | 9,031,680 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=320,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=62720,padding=0,stride=2,w=28}` | 1 | 8,028,160 | cpu | cpu | - |
| `conv2d{bias=0,cin=32,cout=64,dilation=1,groups=1,h=112,kh=1,kw=1,out_elements=200704,padding=0,stride=2,w=112}` | 1 | 6,422,528 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=100352,padding=0,stride=2,w=56}` | 1 | 6,422,528 | cpu | cpu | - |
| `conv2d{bias=0,cin=768,cout=768,dilation=1,groups=48,h=14,kh=3,kw=3,out_elements=37632,padding=1,stride=2,w=14}` | 1 | 5,419,008 | cpu | cpu | - |
| `conv2d{bias=0,cin=768,cout=768,dilation=1,groups=48,h=7,kh=3,kw=3,out_elements=37632,padding=1,stride=1,w=7}` | 1 | 5,419,008 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=1000}` | 1 | 768,000 | cpu | cpu | - |
| `conv2d{bias=1,cin=320,cout=80,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=80,padding=0,stride=1,w=1}` | 7 | 25,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=80,cout=320,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=320,padding=0,stride=1,w=1}` | 7 | 25,600 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=192,cout=768,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=768,padding=0,stride=1,w=1}` | 1 | 147,456 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=768,cout=192,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=192,padding=0,stride=1,w=1}` | 1 | 147,456 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=768,cout=80,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=80,padding=0,stride=1,w=1}` | 1 | 61,440 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=80,cout=768,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=768,padding=0,stride=1,w=1}` | 1 | 61,440 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=32,cout=320,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=320,padding=0,stride=1,w=1}` | 1 | 10,240 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=320,cout=32,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=32,padding=0,stride=1,w=1}` | 1 | 10,240 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=32,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=32,padding=0,stride=1,w=1}` | 2 | 4,096 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=32,cout=128,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=128,padding=0,stride=1,w=1}` | 2 | 4,096 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=16,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=16,padding=0,stride=1,w=1}` | 1 | 2,048 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=16,cout=128,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=128,padding=0,stride=1,w=1}` | 1 | 2,048 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=64,cout=8,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=8,padding=0,stride=1,w=1}` | 1 | 512 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=8,cout=64,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=64,padding=0,stride=1,w=1}` | 1 | 512 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=320,hw=196}` | 24 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=784}` | 9 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=62720,operands=tensor}` | 8 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `mean{numel=62720,out=320}` | 8 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=62720,operands=tensor}` | 8 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=62720}` | 8 | 0 | cpu | cpu | - |
| `relu{numel=80}` | 8 | 0 | cpu | cpu | - |
| `sigmoid{numel=320}` | 8 | 0 | cpu | cpu | - |
| `batchnorm{channels=768,hw=49}` | 6 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=100352,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=64,hw=3136}` | 3 | 0 | cpu | cpu | - |
| `mean{numel=100352,out=128}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=100352,operands=tensor}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=100352}` | 3 | 0 | cpu | cpu | - |
| `relu{numel=32}` | 3 | 0 | cpu | cpu | - |
| `sigmoid{numel=128}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=37632,operands=tensor}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `mean{numel=37632,out=768}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=37632,operands=tensor}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=37632}` | 2 | 0 | cpu | cpu | - |
| `sigmoid{numel=768}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=768,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=200704,operands=tensor}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=768,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=32,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=768,hw=196}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=200704,out=64}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=200704,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=16}` | 1 | 0 | cpu | cpu | - |
| `relu{numel=192}` | 1 | 0 | cpu | cpu | - |
| `relu{numel=200704}` | 1 | 0 | cpu | cpu | - |
| `relu{numel=8}` | 1 | 0 | cpu | cpu | - |
| `sigmoid{numel=64}` | 1 | 0 | cpu | cpu | - |

