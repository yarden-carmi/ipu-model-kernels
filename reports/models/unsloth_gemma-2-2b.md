# unsloth/gemma-2-2b

- domain: llm, family: gemma2, size: 2B, params at full depth: 2614.3M
- canonical: google/gemma-2-2b
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [26, 2], "scales": {"model.layers": 13.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2304,m=1,n=9216}` | 52 | 21,233,664 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=1,n=256000}` | 1 | 589,824,000 | cpu | cpu | - |
| `linear{bias=0,k=9216,m=1,n=2304}` | 26 | 21,233,664 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=2304}` | 26 | 4,718,592 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=1,n=1024}` | 52 | 2,359,296 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=1,n=2048}` | 26 | 4,718,592 | cpu | cpu | - |
| `bmm{b=8,k=256,m=1,n=257}` | 26 | 526,336 | cpu | cpu | - |
| `bmm{b=8,k=257,m=1,n=256}` | 26 | 526,336 | cpu | cpu | - |
| `rmsnorm{channels=2304,tokens=1}` | 105 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=2304,operands=tensor}` | 52 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=263168}` | 52 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2056,operands=scalar}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=1024,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=2048,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=2056,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=1024}` | 26 | 0 | cpu | cpu | - |
| `concat{numel=2048}` | 26 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=2056,operands=scalar}` | 26 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=9216}` | 26 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=9216,operands=tensor}` | 26 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1024}` | 26 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 26 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=257,rows=8}` | 26 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `tanh{numel=2056}` | 26 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=256,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=256}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=256}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=256000,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2304,tokens=1,vocab=256000}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256000,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=128,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=2304,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sin{numel=256}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `tanh{numel=256000}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2304,m=256,n=9216}` | 52 | 5,435,817,984 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=256,n=256000}` | 1 | 150,994,944,000 | cpu | cpu | - |
| `linear{bias=0,k=9216,m=256,n=2304}` | 26 | 5,435,817,984 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=2304}` | 26 | 1,207,959,552 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=256,n=1024}` | 52 | 603,979,776 | cpu | cpu | - |
| `linear{bias=0,k=2304,m=256,n=2048}` | 26 | 1,207,959,552 | cpu | cpu | - |
| `bmm{b=8,k=256,m=256,n=256}` | 52 | 134,217,728 | cpu | cpu | - |
| `rmsnorm{channels=2304,tokens=256}` | 105 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=589824,operands=tensor}` | 52 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=524288,operands=scalar}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=262144,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=524288,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=524288,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=262144}` | 26 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 26 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=524288,operands=scalar}` | 26 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=2359296}` | 26 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2359296,operands=tensor}` | 26 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 26 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 26 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=2048}` | 26 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `tanh{numel=524288}` | 26 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=256,operands=scalar}` | 5 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 2 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=65536,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 2 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=65536000,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2304,tokens=256,vocab=256000}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=65536000,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32768,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=589824,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sin{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `tanh{numel=65536000}` | 1 | 0 | cpu | cpu | - |

