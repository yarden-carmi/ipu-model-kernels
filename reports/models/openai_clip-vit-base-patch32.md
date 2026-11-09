# openai/clip-vit-base-patch32

- domain: multimodal, family: clip, size: 151M, params at full depth: 151.3M
- canonical: openai/clip-vit-base-patch32
- depth scaling: `{"_scales_from": [1, 1], "scales": {"text_model.encoder.layers": 6.0, "vision_model.encoder.layers": 6.0}, "text_config.num_hidden_layers": [12, 2], "vision_config.num_hidden_layers": [12, 2]}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=50,n=768}` | 12 | 117,964,800 | cpu | cpu | - |
| `linear{bias=1,k=768,m=50,n=3072}` | 12 | 117,964,800 | cpu | cpu | - |
| `linear{bias=1,k=768,m=50,n=768}` | 48 | 29,491,200 | cpu | cpu | - |
| `linear{bias=1,k=2048,m=64,n=512}` | 12 | 67,108,864 | cpu | cpu | - |
| `linear{bias=1,k=512,m=64,n=2048}` | 12 | 67,108,864 | cpu | cpu | - |
| `linear{bias=1,k=512,m=64,n=512}` | 48 | 16,777,216 | cpu | cpu | - |
| `conv2d{bias=0,cin=3,cout=768,dilation=1,groups=1,h=224,kh=32,kw=32,out_elements=37632,padding=0,stride=32,w=224}` | 1 | 115,605,504 | cpu | cpu | - |
| `bmm{b=8,k=64,m=64,n=64}` | 24 | 2,097,152 | chip-emu | chip-emu | matmul_64x64x64 (chip-emu, exact, fp32-exact) |
| `bmm{b=12,k=50,m=50,n=64}` | 12 | 1,920,000 | cpu | cpu | - |
| `bmm{b=12,k=64,m=50,n=50}` | 12 | 1,920,000 | cpu | cpu | - |
| `linear{bias=0,k=768,m=1,n=512}` | 1 | 393,216 | cpu | cpu | - |
| `linear{bias=0,k=512,m=1,n=512}` | 1 | 262,144 | cpu | cpu | - |
| `bmm{b=1,k=512,m=1,n=1}` | 1 | 512 | cpu | cpu | - |
| `add{broadcast=0,numel=32768,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=38400,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=512,layout=channels_last,tokens=64}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=50}` | 25 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=32768,operands=tensor}` | 12 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=30000,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `quick_gelu{numel=131072}` | 12 | 0 | cpu | cpu | - |
| `quick_gelu{numel=153600}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=50,rows=600}` | 12 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=512}` | 12 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=64,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `div{broadcast=1,numel=512,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `pow{numel=1}` | 2 | 0 | cpu | cpu | - |
| `pow{numel=512}` | 2 | 0 | cpu | cpu | - |
| `sum{numel=512,out=1}` | 2 | 0 | cpu | cpu | - |
| `argmax{numel=64,out=1}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=37632,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=38400}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=512,tokens=64,vocab=49408}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=512,tokens=64,vocab=77}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=50,vocab=50}` | 1 | 0 | cpu | cpu | - |
| `exp{numel=1}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=512}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=1}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=4096}` | 1 | 0 | cpu | cpu | - |

