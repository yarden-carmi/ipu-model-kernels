# EleutherAI/pythia-160m

- domain: llm, family: gpt-neox, size: 160M, params at full depth: 162.3M
- canonical: EleutherAI/pythia-160m
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"gpt_neox.layers": 6.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=768,m=1,n=50304}` | 1 | 38,633,472 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=1,n=768}` | 12 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=3072}` | 12 | 2,359,296 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=2304}` | 12 | 1,769,472 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=768}` | 12 | 589,824 | cpu | cpu | - |
| `bmm{b=12,k=257,m=1,n=64}` | 12 | 197,376 | cpu | cpu | - |
| `bmm{b=12,k=64,m=1,n=257}` | 12 | 197,376 | cpu | cpu | - |
| `mul{broadcast=1,numel=192,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=1}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=192,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=768,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=192}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=197376}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=768}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=96}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=3084,operands=tensor}` | 12 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu{numel=3072}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3084,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=257,rows=12}` | 12 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=16,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=16}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=16}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=1,vocab=50304}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=16}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=768,m=256,n=50304}` | 1 | 9,890,168,832 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=256,n=768}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=2304}` | 12 | 452,984,832 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=768}` | 12 | 150,994,944 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 12 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 12 | 50,331,648 | cpu | cpu | - |
| `mul{broadcast=1,numel=49152,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=196608,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=49152,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=196608}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=49152}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=24576}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=786432,operands=tensor}` | 12 | 0 | cpu | cpu | - |
| `gelu{numel=786432}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=4096,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=4096}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=4096}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=50304}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=4096}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

