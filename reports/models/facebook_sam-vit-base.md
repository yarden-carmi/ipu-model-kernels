# facebook/sam-vit-base

- domain: vision-segmentation, family: sam, size: 94M, params at full depth: 93.7M
- canonical: facebook/sam-vit-base
- depth scaling: `{"_scales_from": [1, 1], "scales": {"vision_encoder.layers": 6.0}, "vision_config.num_hidden_layers": [12, 2]}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=4096,n=768}` | 12 | 9,663,676,416 | cpu | cpu | - |
| `linear{bias=1,k=768,m=4096,n=3072}` | 12 | 9,663,676,416 | cpu | cpu | - |
| `linear{bias=1,k=768,m=4900,n=2304}` | 12 | 8,670,412,800 | cpu | cpu | - |
| `linear{bias=1,k=768,m=4900,n=768}` | 12 | 2,890,137,600 | cpu | cpu | - |
| `bmm{b=300,k=196,m=196,n=64}` | 12 | 737,587,200 | cpu | cpu | - |
| `bmm{b=300,k=64,m=196,n=196}` | 12 | 737,587,200 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=1048576,padding=1,stride=1,w=64}` | 1 | 2,415,919,104 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=3,cout=768,dilation=1,groups=1,h=1024,kh=16,kw=16,out_elements=3145728,padding=0,stride=16,w=1024}` | 1 | 2,415,919,104 | cpu | cpu | - |
| `conv_transpose2d{bias=1,cin=256,cout=64,dilation=1,groups=1,h=64,kh=2,kw=2,out_elements=1048576,padding=0,stride=2,w=64}` | 1 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=1,k=256,m=4096,n=128}` | 8 | 134,217,728 | cpu | cpu | - |
| `conv2d{bias=0,cin=768,cout=256,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=64}` | 1 | 805,306,368 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv_transpose2d{bias=1,cin=64,cout=32,dilation=1,groups=1,h=128,kh=2,kw=2,out_elements=2097152,padding=0,stride=2,w=128}` | 1 | 536,870,912 | cpu | cpu | - |
| `linear{bias=1,k=128,m=4096,n=256}` | 2 | 134,217,728 | cpu | cpu | - |
| `bmm{b=8,k=16,m=7,n=4096}` | 3 | 3,670,016 | cpu | cpu | - |
| `bmm{b=8,k=4096,m=7,n=16}` | 3 | 3,670,016 | cpu | cpu | - |
| `bmm{b=1,k=32,m=4,n=65536}` | 1 | 8,388,608 | cpu | cpu | - |
| `bmm{b=8,k=16,m=4096,n=7}` | 2 | 3,670,016 | cpu | cpu | - |
| `bmm{b=8,k=7,m=4096,n=16}` | 2 | 3,670,016 | cpu | cpu | - |
| `linear{bias=1,k=2048,m=7,n=256}` | 2 | 3,670,016 | cpu | cpu | - |
| `linear{bias=1,k=256,m=7,n=2048}` | 2 | 3,670,016 | cpu | cpu | - |
| `linear{bias=1,k=256,m=7,n=256}` | 8 | 458,752 | cpu | cpu | - |
| `linear{bias=1,k=256,m=7,n=128}` | 7 | 229,376 | cpu | cpu | - |
| `bmm{b=64,k=2,m=64,n=128}` | 1 | 1,048,576 | cpu | cpu | - |
| `linear{bias=1,k=128,m=7,n=256}` | 3 | 229,376 | cpu | cpu | - |
| `linear{bias=1,k=256,m=1,n=256}` | 10 | 65,536 | cpu | cpu | - |
| `linear{bias=1,k=256,m=1,n=32}` | 4 | 8,192 | cpu | cpu | - |
| `bmm{b=8,k=32,m=7,n=7}` | 2 | 12,544 | cpu | cpu | - |
| `bmm{b=8,k=7,m=7,n=32}` | 2 | 12,544 | cpu | cpu | - |
| `linear{bias=1,k=256,m=1,n=4}` | 1 | 1,024 | cpu | cpu | - |
| `bmm{b=1,k=2,m=2,n=128}` | 1 | 512 | cpu | cpu | - |
| `mul{broadcast=0,numel=14,operands=scalar}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=3145728,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=196,operands=scalar}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=823200,schema=aten::einsum}` | 24 | 0 | cpu | cpu | - |
| `gather{numel=12544}` | 24 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=4096}` | 24 | 0 | cpu | cpu | - |
| `sub{broadcast=1,numel=196,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `upsample{channels=64,h=64,mode=linear1d,out_elements=1728,w=27}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=11524800,operands=tensor}` | 12 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1792,operands=tensor}` | 12 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=11524800,operands=tensor}` | 12 | 0 | cpu | cpu | - |
| `aten{numel=11524800,schema=aten::reshape_as}` | 12 | 0 | cpu | cpu | - |
| `gelu{numel=12582912}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3763200,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `pad{numel=3763200}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=196,rows=58800}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `relu{numel=256}` | 10 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1048576,operands=tensor}` | 8 | 0 | cpu | cpu | - |
| `layernorm{channels=256,layout=channels_last,tokens=7}` | 7 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=229376,operands=scalar}` | 5 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=512}` | 4 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=4096,rows=56}` | 3 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=512,operands=tensor}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=1048576,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `cumsum{numel=4096,out=4096}` | 2 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=2,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=4096,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `layernorm{channels=256,layout=channels_last,tokens=4096}` | 2 | 0 | cpu | cpu | - |
| `layernorm{channels=64,layout=channels_last,tokens=16384}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=392,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=14336}` | 2 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=7,rows=32768}` | 2 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=7,rows=56}` | 2 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `sub{broadcast=0,numel=4096,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=2,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=1048576}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=1280}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=1792}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=2}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=4}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=512}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=8192}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=256}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=524288}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=1048576}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=2097152}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=128,layout=channels_last,tokens=8192}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=4,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=524288,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8192,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1}` | 1 | 0 | cpu | cpu | - |
| `repeat{numel=1048576}` | 1 | 0 | cpu | cpu | - |
| `repeat{numel=1280}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=256}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=524288}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=4,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=8192,operands=scalar}` | 1 | 0 | cpu | cpu | - |

