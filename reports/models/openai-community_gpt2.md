# openai-community/gpt2

- domain: llm, family: gpt2, size: 124M, params at full depth: 124.4M
- canonical: openai-community/gpt2
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"transformer.h": 6.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=768,m=1,n=50257}` | 1 | 38,597,376 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=1,n=768}` | 12 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=3072}` | 12 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=2304}` | 12 | 1,769,472 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=768}` | 12 | 589,824 | cpu | cpu | - |
| `bmm{b=12,k=257,m=1,n=64}` | 12 | 197,376 | cpu | cpu | - |
| `bmm{b=12,k=64,m=1,n=257}` | 12 | 197,376 | cpu | cpu | - |
| `add{broadcast=0,numel=768,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=768,layout=channels_last,tokens=1}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `concat{numel=197376}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=3084,operands=tensor}` | 12 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu_tanh{numel=3072}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3084,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=257,rows=12}` | 12 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `embedding{dim=768,tokens=1,vocab=1024}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=1,vocab=50257}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=768,m=256,n=50257}` | 1 | 9,880,928,256 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=256,n=768}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=2304}` | 12 | 452,984,832 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=768}` | 12 | 150,994,944 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 12 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 12 | 50,331,648 | cpu | cpu | - |
| `add{broadcast=0,numel=196608,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=1,numel=786432,operands=tensor}` | 12 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=786432}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=1024}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=50257}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

