# allenai/OLMoE-1B-7B-0924

- domain: llm, family: olmoe, size: 7B-A1B, params at full depth: 6919.2M
- canonical: allenai/OLMoE-1B-7B-0924
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [16, 2], "scales": {"model.layers": 8.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=1,n=2048}` | 64 | 4,194,304 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=50304}` | 1 | 103,022,592 | cpu | cpu | - |
| `bmm{b=16,k=128,m=1,n=257}` | 16 | 526,336 | cpu | cpu | - |
| `bmm{b=16,k=257,m=1,n=128}` | 16 | 526,336 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=64}` | 16 | 131,072 | cpu | cpu | - |
| `rmsnorm{channels=2048,tokens=1}` | 65 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=2048,operands=tensor}` | 64 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 64 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=16384,schema=aten::_grouped_mm}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=2048}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=526336}` | 32 | 0 | cpu | cpu | - |
| `gather{numel=16384}` | 32 | 0 | cpu | cpu | - |
| `neg{numel=1024}` | 32 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=4112,operands=tensor}` | 16 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `cumsum{numel=64,out=64}` | 16 | 0 | cpu | cpu | - |
| `gather{numel=8}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=4112,operands=scalar}` | 16 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8192,operands=tensor}` | 16 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 16 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `silu{numel=8192}` | 16 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=16}` | 16 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=1}` | 16 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `sort{numel=8,out=8}` | 16 | 0 | cpu | cpu | - |
| `sum{numel=16384,out=2048}` | 16 | 0 | cpu | cpu | - |
| `topk{numel=64,out=8}` | 16 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=1,vocab=50304}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=256,n=2048}` | 64 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=50304}` | 1 | 26,373,783,552 | cpu | cpu | - |
| `bmm{b=16,k=128,m=256,n=256}` | 16 | 134,217,728 | cpu | cpu | - |
| `bmm{b=16,k=256,m=256,n=128}` | 16 | 134,217,728 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=64}` | 16 | 33,554,432 | cpu | cpu | - |
| `rmsnorm{channels=2048,tokens=256}` | 65 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 64 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 64 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=4194304,schema=aten::_grouped_mm}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 32 | 0 | cpu | cpu | - |
| `gather{numel=4194304}` | 32 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 32 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=1048576,operands=tensor}` | 16 | 0 | cpu | cpu | - |
| `cumsum{numel=64,out=64}` | 16 | 0 | cpu | cpu | - |
| `gather{numel=2048}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1048576,operands=scalar}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=tensor}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=4194304,operands=tensor}` | 16 | 0 | cpu | cpu | - |
| `silu{numel=2097152}` | 16 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=4096}` | 16 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=256}` | 16 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `sort{numel=2048,out=2048}` | 16 | 0 | cpu | cpu | - |
| `sum{numel=4194304,out=524288}` | 16 | 0 | cpu | cpu | - |
| `topk{numel=16384,out=2048}` | 16 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=256,vocab=50304}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

