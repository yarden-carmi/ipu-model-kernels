# ibm-granite/granite-3.1-2b-base

- domain: llm, family: granite, size: 2B, params at full depth: 2533.5M
- canonical: ibm-granite/granite-3.1-2b-base
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [40, 2], "scales": {"model.layers": 20.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=1,n=8192}` | 80 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=1,n=2048}` | 40 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=2048}` | 80 | 4,194,304 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=49152}` | 1 | 100,663,296 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=512}` | 80 | 1,048,576 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=64}` | 40 | 526,336 | cpu | cpu | - |
| `bmm{b=32,k=64,m=1,n=257}` | 40 | 526,336 | cpu | cpu | - |
| `add{broadcast=0,numel=2048,operands=tensor}` | 120 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `mul{broadcast=0,numel=2048,operands=scalar}` | 81 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `rmsnorm{channels=2048,tokens=1}` | 81 | 0 | cpu | cpu | - |
| `concat{numel=131584}` | 80 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=512,operands=tensor}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=512,operands=tensor}` | 40 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=8224,operands=tensor}` | 40 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=2048}` | 40 | 0 | cpu | cpu | - |
| `concat{numel=512}` | 40 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=8192,operands=tensor}` | 40 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 40 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1024}` | 40 | 0 | cpu | cpu | - |
| `neg{numel=256}` | 40 | 0 | cpu | cpu | - |
| `silu{numel=8192}` | 40 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=32}` | 40 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=64,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=64}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=64}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=49152,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=1,vocab=49152}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=64}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=256,n=8192}` | 80 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=256,n=2048}` | 40 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=2048}` | 80 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=49152}` | 1 | 25,769,803,776 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=512}` | 80 | 268,435,456 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=64}` | 40 | 134,217,728 | cpu | cpu | - |
| `bmm{b=32,k=64,m=256,n=256}` | 40 | 134,217,728 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 120 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=524288,operands=scalar}` | 81 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `rmsnorm{channels=2048,tokens=256}` | 81 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=131072,operands=tensor}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=131072,operands=tensor}` | 40 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 40 | 0 | cpu | cpu | - |
| `concat{numel=131072}` | 40 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 40 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 40 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=tensor}` | 40 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 40 | 0 | cpu | cpu | - |
| `neg{numel=65536}` | 40 | 0 | cpu | cpu | - |
| `silu{numel=2097152}` | 40 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 40 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=16384,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=12582912,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=256,vocab=49152}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

