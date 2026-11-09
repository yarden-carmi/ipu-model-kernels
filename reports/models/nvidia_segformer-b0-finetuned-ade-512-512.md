# nvidia/segformer-b0-finetuned-ade-512-512

- domain: vision-segmentation, family: segformer, size: 3.8M, params at full depth: 3.8M
- canonical: nvidia/segformer-b0-finetuned-ade-512-512
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=1024,cout=256,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=802816,padding=0,stride=1,w=56}` | 1 | 822,083,584 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=256,cout=150,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=470400,padding=0,stride=1,w=56}` | 1 | 120,422,400 | cpu | cpu | - |
| `linear{bias=1,k=160,m=196,n=640}` | 2 | 20,070,400 | cpu | cpu | - |
| `linear{bias=1,k=640,m=196,n=160}` | 2 | 20,070,400 | cpu | cpu | - |
| `linear{bias=1,k=64,m=784,n=256}` | 3 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=256,m=49,n=256}` | 9 | 3,211,264 | cpu | cpu | - |
| `linear{bias=1,k=1024,m=49,n=256}` | 2 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=128,m=3136,n=32}` | 2 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=256,m=49,n=1024}` | 2 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=256,m=784,n=64}` | 2 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=32,m=3136,n=128}` | 2 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=32,m=3136,n=256}` | 1 | 25,690,112 | cpu | cpu | - |
| `linear{bias=1,k=160,m=196,n=160}` | 4 | 5,017,600 | cpu | cpu | - |
| `conv2d{bias=1,cin=160,cout=256,dilation=1,groups=1,h=14,kh=3,kw=3,out_elements=12544,padding=1,stride=2,w=14}` | 1 | 18,063,360 | cpu | cpu | - |
| `conv2d{bias=1,cin=64,cout=160,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=31360,padding=1,stride=2,w=28}` | 1 | 18,063,360 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=32,dilation=1,groups=1,h=224,kh=7,kw=7,out_elements=100352,padding=3,stride=4,w=224}` | 1 | 14,751,744 | cpu | cpu | - |
| `conv2d{bias=1,cin=32,cout=64,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=50176,padding=1,stride=2,w=56}` | 1 | 14,450,688 | cpu | cpu | - |
| `linear{bias=1,k=32,m=3136,n=32}` | 4 | 3,211,264 | cpu | cpu | - |
| `linear{bias=1,k=64,m=784,n=64}` | 4 | 3,211,264 | cpu | cpu | - |
| `conv2d{bias=1,cin=160,cout=160,dilation=1,groups=1,h=14,kh=2,kw=2,out_elements=7840,padding=0,stride=2,w=14}` | 2 | 5,017,600 | cpu | cpu | - |
| `bmm{b=1,k=32,m=3136,n=49}` | 2 | 4,917,248 | cpu | cpu | - |
| `bmm{b=1,k=49,m=3136,n=32}` | 2 | 4,917,248 | cpu | cpu | - |
| `linear{bias=1,k=160,m=196,n=256}` | 1 | 8,028,160 | cpu | cpu | - |
| `conv2d{bias=1,cin=128,cout=128,dilation=1,groups=128,h=56,kh=3,kw=3,out_elements=401408,padding=1,stride=1,w=56}` | 2 | 3,612,672 | chip-emu | chip-emu | depthwise_conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=32,cout=32,dilation=1,groups=1,h=56,kh=8,kw=8,out_elements=1568,padding=0,stride=8,w=56}` | 2 | 3,211,264 | cpu | cpu | - |
| `conv2d{bias=1,cin=64,cout=64,dilation=1,groups=1,h=28,kh=4,kw=4,out_elements=3136,padding=0,stride=4,w=28}` | 2 | 3,211,264 | cpu | cpu | - |
| `linear{bias=1,k=160,m=49,n=160}` | 4 | 1,254,400 | cpu | cpu | - |
| `bmm{b=2,k=32,m=784,n=49}` | 2 | 2,458,624 | cpu | cpu | - |
| `bmm{b=2,k=49,m=784,n=32}` | 2 | 2,458,624 | cpu | cpu | - |
| `conv2d{bias=1,cin=256,cout=256,dilation=1,groups=256,h=28,kh=3,kw=3,out_elements=200704,padding=1,stride=1,w=28}` | 2 | 1,806,336 | chip-emu | chip-emu | depthwise_conv_universal_bias (chip-emu, exact, fp32-exact) |
| `bmm{b=5,k=32,m=196,n=49}` | 2 | 1,536,640 | cpu | cpu | - |
| `bmm{b=5,k=49,m=196,n=32}` | 2 | 1,536,640 | cpu | cpu | - |
| `conv2d{bias=1,cin=640,cout=640,dilation=1,groups=640,h=14,kh=3,kw=3,out_elements=125440,padding=1,stride=1,w=14}` | 2 | 1,128,960 | chip-emu | chip-emu | depthwise_conv_universal_bias (chip-emu, exact, fp32-exact) |
| `bmm{b=8,k=32,m=49,n=49}` | 2 | 614,656 | cpu | cpu | - |
| `bmm{b=8,k=49,m=49,n=32}` | 2 | 614,656 | cpu | cpu | - |
| `conv2d{bias=1,cin=1024,cout=1024,dilation=1,groups=1024,h=7,kh=3,kw=3,out_elements=50176,padding=1,stride=1,w=7}` | 2 | 451,584 | chip-emu | chip-emu | depthwise_conv_universal_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=64,m=49,n=64}` | 4 | 200,704 | cpu | cpu | - |
| `linear{bias=1,k=32,m=49,n=32}` | 4 | 50,176 | cpu | cpu | - |
| `layernorm{channels=160,layout=channels_last,tokens=196}` | 6 | 0 | cpu | cpu | - |
| `layernorm{channels=256,layout=channels_last,tokens=49}` | 6 | 0 | cpu | cpu | - |
| `layernorm{channels=32,layout=channels_last,tokens=3136}` | 6 | 0 | cpu | cpu | - |
| `layernorm{channels=64,layout=channels_last,tokens=784}` | 6 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=100352,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=12544,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=31360,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=50176,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=50176,schema=aten::flatten.using_ints}` | 4 | 0 | cpu | cpu | - |
| `aten{numel=100352,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=12544,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=125440,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=200704,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=31360,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=401408,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=125440}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=200704}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=401408}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=50176}` | 2 | 0 | cpu | cpu | - |
| `layernorm{channels=160,layout=channels_last,tokens=49}` | 2 | 0 | cpu | cpu | - |
| `layernorm{channels=32,layout=channels_last,tokens=49}` | 2 | 0 | cpu | cpu | - |
| `layernorm{channels=64,layout=channels_last,tokens=49}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=153664,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=19208,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=48020,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=76832,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=49,rows=1568}` | 2 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=49,rows=3136}` | 2 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=49,rows=392}` | 2 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=49,rows=980}` | 2 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `batchnorm{channels=256,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=3211264}` | 1 | 0 | cpu | cpu | - |
| `relu{numel=802816}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=256,h=14,mode=bilinear2d,out_elements=802816,w=14}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=256,h=28,mode=bilinear2d,out_elements=802816,w=28}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=256,h=56,mode=bilinear2d,out_elements=802816,w=56}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=256,h=7,mode=bilinear2d,out_elements=802816,w=7}` | 1 | 0 | cpu | cpu | - |

