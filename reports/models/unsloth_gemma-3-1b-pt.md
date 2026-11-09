# unsloth/gemma-3-1b-pt

- domain: llm, family: gemma3, size: 1B, params at full depth: 999.9M
- canonical: google/gemma-3-1b-pt
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [26, 2], "scales": {"model.layers": 13.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=1152,m=1,n=6912}` | 52 | 7,962,624 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=1,n=262144}` | 1 | 301,989,888 | cpu | cpu | - |
| `linear{bias=0,k=6912,m=1,n=1152}` | 26 | 7,962,624 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=1,n=1152}` | 26 | 1,179,648 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=1,n=1024}` | 26 | 1,179,648 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=1,n=256}` | 52 | 294,912 | cpu | cpu | - |
| `bmm{b=4,k=256,m=1,n=257}` | 26 | 263,168 | cpu | cpu | - |
| `bmm{b=4,k=257,m=1,n=256}` | 26 | 263,168 | cpu | cpu | - |
| `rmsnorm{channels=1152,tokens=1}` | 105 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1152,operands=tensor}` | 52 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=65792}` | 52 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `concat{numel=256}` | 27 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1024,operands=tensor}` | 26 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=tensor}` | 26 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=1028,operands=tensor}` | 26 | 0 | cpu | cpu | - |
| `concat{numel=1024}` | 26 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=6912}` | 26 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1028,operands=scalar}` | 26 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=6912,operands=tensor}` | 26 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=128}` | 26 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 26 | 0 | cpu | cpu | - |
| `rmsnorm{channels=256,tokens=1}` | 26 | 0 | cpu | cpu | - |
| `rmsnorm{channels=256,tokens=4}` | 26 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=257,rows=4}` | 26 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=257,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 2 | 0 | cpu | cpu | - |
| `cos{numel=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1152,tokens=1,vocab=262144}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1152,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=128,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sin{numel=256}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=1152,m=256,n=6912}` | 52 | 2,038,431,744 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=256,n=262144}` | 1 | 77,309,411,328 | cpu | cpu | - |
| `linear{bias=0,k=6912,m=256,n=1152}` | 26 | 2,038,431,744 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=256,n=1152}` | 26 | 301,989,888 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=256,n=1024}` | 26 | 301,989,888 | cpu | cpu | - |
| `linear{bias=0,k=1152,m=256,n=256}` | 52 | 75,497,472 | cpu | cpu | - |
| `bmm{b=4,k=256,m=256,n=256}` | 52 | 67,108,864 | cpu | cpu | - |
| `rmsnorm{channels=1152,tokens=256}` | 105 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=294912,operands=tensor}` | 52 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=65536,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 52 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `concat{numel=65536}` | 27 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=262144,operands=tensor}` | 26 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=65536,operands=tensor}` | 26 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=262144,operands=tensor}` | 26 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 26 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=1769472}` | 26 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1769472,operands=tensor}` | 26 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=262144,operands=scalar}` | 26 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=131072}` | 26 | 0 | cpu | cpu | - |
| `neg{numel=32768}` | 26 | 0 | cpu | cpu | - |
| `rmsnorm{channels=256,tokens=1024}` | 26 | 0 | cpu | cpu | - |
| `rmsnorm{channels=256,tokens=256}` | 26 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=1024}` | 26 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `aten{numel=256,schema=aten::diff}` | 2 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=65536,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 2 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `cos{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1152,tokens=256,vocab=262144}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=294912,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=32768,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sin{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | cpu | cpu | - |

