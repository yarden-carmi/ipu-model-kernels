# google/siglip-base-patch16-224

- domain: multimodal, family: siglip, size: 203M, params at full depth: 203.2M
- canonical: google/siglip-base-patch16-224
- depth scaling: `{"_scales_from": [1, 1], "scales": {"text_model.encoder.layers": 6.0, "vision_model.encoder.layers": 6.0}, "text_config.num_hidden_layers": [12, 2], "vision_config.num_hidden_layers": [12, 2]}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=196,n=768}` | 12 | 462,422,016 | cpu | cpu | - |
| `linear{bias=1,k=768,m=196,n=3072}` | 12 | 462,422,016 | cpu | cpu | - |
| `linear{bias=1,k=768,m=196,n=768}` | 48 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=64,n=768}` | 12 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=768,m=64,n=3072}` | 12 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=768,m=64,n=768}` | 48 | 37,748,736 | cpu | cpu | - |
| `bmm{b=12,k=196,m=196,n=64}` | 12 | 29,503,488 | cpu | cpu | - |
| `bmm{b=12,k=64,m=196,n=196}` | 12 | 29,503,488 | cpu | cpu | - |
| `linear{bias=1,k=768,m=196,n=1536}` | 1 | 231,211,008 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=768,dilation=1,groups=1,h=224,kh=16,kw=16,out_elements=150528,padding=valid,stride=16,w=224}` | 1 | 115,605,504 | cpu | cpu | - |
| `bmm{b=12,k=64,m=64,n=64}` | 24 | 3,145,728 | chip-emu | chip-emu | matmul_64x64x64 (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=3072,m=1,n=768}` | 1 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=3072}` | 1 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=768}` | 3 | 589,824 | cpu | cpu | - |
| `bmm{b=12,k=196,m=1,n=64}` | 1 | 150,528 | cpu | cpu | - |
| `bmm{b=12,k=64,m=1,n=196}` | 1 | 150,528 | cpu | cpu | - |
| `bmm{b=1,k=768,m=1,n=1}` | 1 | 768 | cpu | cpu | - |
| `add{broadcast=0,numel=150528,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=49152,operands=tensor}` | 25 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=768,layout=channels_last,tokens=196}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=64}` | 25 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=196608}` | 12 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=602112}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=460992,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=49152,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=196,rows=2352}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=768}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `div{broadcast=1,numel=768,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `norm{numel=768,out=1}` | 2 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=768,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=150528,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=301056,schema=aten::unflatten.int}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=196,vocab=196}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=64,vocab=32000}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=64,vocab=64}` | 1 | 0 | cpu | cpu | - |
| `exp{numel=1}` | 1 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=3072}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=1}` | 1 | 0 | cpu | cpu | - |
| `mean{numel=2352,out=196}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=768,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `repeat{numel=768}` | 1 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=196,rows=12}` | 1 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |

