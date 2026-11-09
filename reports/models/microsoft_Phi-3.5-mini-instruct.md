# microsoft/Phi-3.5-mini-instruct

- domain: llm, family: phi3, size: 3.8B, params at full depth: 3821.1M
- canonical: microsoft/Phi-3.5-mini-instruct
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [32, 2], "scales": {"model.layers": 16.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=3072,m=1,n=16384}` | 32 | 50,331,648 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=1,n=9216}` | 32 | 28,311,552 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=1,n=3072}` | 32 | 25,165,824 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=1,n=3072}` | 32 | 9,437,184 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=1,n=32064}` | 1 | 98,500,608 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=96}` | 32 | 789,504 | cpu | cpu | - |
| `bmm{b=32,k=96,m=1,n=257}` | 32 | 789,504 | cpu | cpu | - |
| `add{broadcast=0,numel=3072,operands=tensor}` | 128 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=3072}` | 128 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=3072,operands=tensor}` | 128 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `rmsnorm{channels=3072,tokens=1}` | 65 | 0 | cpu | cpu | - |
| `concat{numel=789504}` | 64 | 0 | cpu | cpu | - |
| `neg{numel=1536}` | 64 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=8224,operands=tensor}` | 32 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8192,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `silu{numel=8192}` | 32 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=32}` | 32 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=96,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `amax{numel=1,out=1}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=96}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=96}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=3072,tokens=1,vocab=32064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=48,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=48}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=96}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=3072,m=256,n=16384}` | 32 | 12,884,901,888 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=256,n=9216}` | 32 | 7,247,757,312 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=256,n=3072}` | 32 | 6,442,450,944 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=256,n=3072}` | 32 | 2,415,919,104 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=256,n=32064}` | 1 | 25,216,155,648 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=96}` | 32 | 201,326,592 | cpu | cpu | - |
| `bmm{b=32,k=96,m=256,n=256}` | 32 | 201,326,592 | cpu | cpu | - |
| `add{broadcast=0,numel=786432,operands=tensor}` | 128 | 0 | cpu | cpu | - |
| `concat{numel=786432}` | 128 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=786432,operands=tensor}` | 128 | 0 | cpu | cpu | - |
| `rmsnorm{channels=3072,tokens=256}` | 65 | 0 | cpu | cpu | - |
| `neg{numel=393216}` | 64 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `silu{numel=2097152}` | 32 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=24576,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `amax{numel=256,out=1}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=24576}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=24576}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=48,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=3072,tokens=256,vocab=32064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=48,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=48,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=12288,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `pow{numel=48}` | 1 | 0 | cpu | cpu | - |
| `reciprocal{numel=48}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=48}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=24576}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | cpu | cpu | - |

