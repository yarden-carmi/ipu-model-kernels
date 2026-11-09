# HuggingFaceTB/SmolLM2-135M

- domain: llm, family: llama, size: 135M, params at full depth: 134.5M
- canonical: HuggingFaceTB/SmolLM2-135M
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [30, 2], "scales": {"model.layers": 15.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=576,m=1,n=1536}` | 60 | 884,736 | cpu | cpu | - |
| `linear{bias=0,k=576,m=1,n=49152}` | 1 | 28,311,552 | cpu | cpu | - |
| `linear{bias=0,k=1536,m=1,n=576}` | 30 | 884,736 | cpu | cpu | - |
| `linear{bias=0,k=576,m=1,n=576}` | 60 | 331,776 | cpu | cpu | - |
| `linear{bias=0,k=576,m=1,n=192}` | 60 | 110,592 | cpu | cpu | - |
| `bmm{b=9,k=257,m=1,n=64}` | 30 | 148,032 | cpu | cpu | - |
| `bmm{b=9,k=64,m=1,n=257}` | 30 | 148,032 | cpu | cpu | - |
| `add{broadcast=0,numel=576,operands=tensor}` | 90 | 0 | cpu | cpu | - |
| `rmsnorm{channels=576,tokens=1}` | 61 | 0 | cpu | cpu | - |
| `concat{numel=49344}` | 60 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=192,operands=tensor}` | 60 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=576,operands=tensor}` | 60 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=192,operands=tensor}` | 30 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=2313,operands=tensor}` | 30 | 0 | cpu | cpu | - |
| `concat{numel=192}` | 30 | 0 | cpu | cpu | - |
| `concat{numel=576}` | 30 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1536,operands=tensor}` | 30 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=2313,operands=scalar}` | 30 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=288}` | 30 | 0 | cpu | cpu | - |
| `neg{numel=96}` | 30 | 0 | cpu | cpu | - |
| `silu{numel=1536}` | 30 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=9}` | 30 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=64,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=64}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=64}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=576,tokens=1,vocab=49152}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=64}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=576,m=256,n=1536}` | 60 | 226,492,416 | cpu | cpu | - |
| `linear{bias=0,k=576,m=256,n=49152}` | 1 | 7,247,757,312 | cpu | cpu | - |
| `linear{bias=0,k=1536,m=256,n=576}` | 30 | 226,492,416 | cpu | cpu | - |
| `linear{bias=0,k=576,m=256,n=576}` | 60 | 84,934,656 | cpu | cpu | - |
| `linear{bias=0,k=576,m=256,n=192}` | 60 | 28,311,552 | cpu | cpu | - |
| `bmm{b=9,k=256,m=256,n=64}` | 30 | 37,748,736 | cpu | cpu | - |
| `bmm{b=9,k=64,m=256,n=256}` | 30 | 37,748,736 | cpu | cpu | - |
| `add{broadcast=0,numel=147456,operands=tensor}` | 90 | 0 | cpu | cpu | - |
| `rmsnorm{channels=576,tokens=256}` | 61 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=147456,operands=tensor}` | 60 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=49152,operands=tensor}` | 60 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=49152,operands=tensor}` | 30 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=589824,operands=tensor}` | 30 | 0 | cpu | cpu | - |
| `concat{numel=147456}` | 30 | 0 | cpu | cpu | - |
| `concat{numel=49152}` | 30 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=393216,operands=tensor}` | 30 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=589824,operands=scalar}` | 30 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=24576}` | 30 | 0 | cpu | cpu | - |
| `neg{numel=73728}` | 30 | 0 | cpu | cpu | - |
| `silu{numel=393216}` | 30 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=256,rows=2304}` | 30 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=16384,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=576,tokens=256,vocab=49152}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

