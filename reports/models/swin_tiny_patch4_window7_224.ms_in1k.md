# swin_tiny_patch4_window7_224.ms_in1k

- domain: vision-transformer, family: swin, size: 28M, params at full depth: 28.3M
- canonical: swin_tiny_patch4_window7_224.ms_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=196,n=384}` | 6 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=384,m=196,n=1536}` | 6 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=384,m=196,n=1152}` | 6 | 86,704,128 | cpu | cpu | - |
| `linear{bias=1,k=192,m=784,n=768}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=49,n=768}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=384,m=3136,n=96}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=768,m=49,n=3072}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=768,m=784,n=192}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=96,m=3136,n=384}` | 2 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=192,m=784,n=576}` | 2 | 86,704,128 | cpu | cpu | - |
| `linear{bias=1,k=384,m=196,n=384}` | 6 | 28,901,376 | cpu | cpu | - |
| `linear{bias=1,k=768,m=49,n=2304}` | 2 | 86,704,128 | cpu | cpu | - |
| `linear{bias=1,k=96,m=3136,n=288}` | 2 | 86,704,128 | cpu | cpu | - |
| `linear{bias=0,k=1536,m=49,n=768}` | 1 | 57,802,752 | cpu | cpu | - |
| `linear{bias=0,k=384,m=784,n=192}` | 1 | 57,802,752 | cpu | cpu | - |
| `linear{bias=0,k=768,m=196,n=384}` | 1 | 57,802,752 | cpu | cpu | - |
| `linear{bias=1,k=192,m=784,n=192}` | 2 | 28,901,376 | cpu | cpu | - |
| `linear{bias=1,k=768,m=49,n=768}` | 2 | 28,901,376 | cpu | cpu | - |
| `linear{bias=1,k=96,m=3136,n=96}` | 2 | 28,901,376 | cpu | cpu | - |
| `bmm{b=192,k=32,m=49,n=49}` | 2 | 14,751,744 | cpu | cpu | - |
| `bmm{b=192,k=49,m=49,n=32}` | 2 | 14,751,744 | cpu | cpu | - |
| `bmm{b=48,k=32,m=49,n=49}` | 6 | 3,687,936 | cpu | cpu | - |
| `bmm{b=48,k=49,m=49,n=32}` | 6 | 3,687,936 | cpu | cpu | - |
| `bmm{b=96,k=32,m=49,n=49}` | 2 | 7,375,872 | cpu | cpu | - |
| `bmm{b=96,k=49,m=49,n=32}` | 2 | 7,375,872 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=96,dilation=1,groups=1,h=224,kh=4,kw=4,out_elements=301056,padding=0,stride=4,w=224}` | 1 | 14,450,688 | cpu | cpu | - |
| `bmm{b=24,k=32,m=49,n=49}` | 2 | 1,843,968 | cpu | cpu | - |
| `bmm{b=24,k=49,m=49,n=32}` | 2 | 1,843,968 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=1000}` | 1 | 768,000 | cpu | cpu | - |
| `add{broadcast=0,numel=75264,operands=tensor}` | 12 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=384,layout=channels_last,tokens=196}` | 12 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=115248,operands=tensor}` | 9 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `pad{numel=75264}` | 7 | 0 | cpu | cpu | - |
| `gather{numel=28812}` | 6 | 0 | cpu | cpu | - |
| `gelu{numel=301056}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=75264,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=49,rows=2352}` | 6 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `layernorm{channels=768,layout=channels_last,tokens=49}` | 5 | 0 | cpu | cpu | - |
| `layernorm{channels=96,layout=channels_last,tokens=3136}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=150528,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=301056,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=37632,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=192,layout=channels_last,tokens=784}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=230496,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=460992,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `pad{numel=150528}` | 3 | 0 | cpu | cpu | - |
| `pad{numel=301056}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=57624,operands=tensor}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gather{numel=14406}` | 2 | 0 | cpu | cpu | - |
| `gather{numel=57624}` | 2 | 0 | cpu | cpu | - |
| `gather{numel=7203}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=1204224}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=150528}` | 2 | 0 | cpu | cpu | - |
| `gelu{numel=602112}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=150528,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=301056,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=37632,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `pad{numel=37632}` | 2 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=49,rows=1176}` | 2 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=49,rows=4704}` | 2 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=49,rows=9408}` | 2 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `aten{numel=150528,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=301056,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=75264,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=1536,layout=channels_last,tokens=49}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=384,layout=channels_last,tokens=784}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=196}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=37632,out=768}` | 1 | 0 | cpu | cpu | - |

