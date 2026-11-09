# google-t5/t5-small

- domain: seq2seq, family: t5, size: 60M, params at full depth: 60.5M
- canonical: google-t5/t5-small
- depth scaling: `{"_scales_from": [1, 1], "num_decoder_layers": [6, 2], "num_hidden_layers": [6, 2], "scales": {"decoder.block": 3.0, "encoder.block": 3.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=512,m=256,n=512}` | 36 | 67,108,864 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=512}` | 6 | 268,435,456 | cpu | cpu | - |
| `linear{bias=0,k=512,m=256,n=2048}` | 6 | 268,435,456 | cpu | cpu | - |
| `linear{bias=0,k=512,m=64,n=32128}` | 1 | 1,052,770,304 | cpu | cpu | - |
| `linear{bias=0,k=512,m=64,n=512}` | 36 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=64,n=512}` | 6 | 67,108,864 | cpu | cpu | - |
| `linear{bias=0,k=512,m=64,n=2048}` | 6 | 67,108,864 | cpu | cpu | - |
| `bmm{b=8,k=256,m=256,n=64}` | 6 | 33,554,432 | cpu | cpu | - |
| `bmm{b=8,k=64,m=256,n=256}` | 6 | 33,554,432 | cpu | cpu | - |
| `bmm{b=8,k=256,m=64,n=64}` | 6 | 8,388,608 | cpu | cpu | - |
| `bmm{b=8,k=64,m=64,n=256}` | 6 | 8,388,608 | cpu | cpu | - |
| `bmm{b=8,k=64,m=64,n=64}` | 12 | 2,097,152 | chip-emu | chip-emu | matmul_64x64x64 (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=32768,operands=tensor}` | 24 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=512,tokens=64}` | 19 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=131072,operands=tensor}` | 18 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=512,tokens=256}` | 13 | 0 | cpu | cpu | - |
| `concat{numel=131072}` | 12 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 7 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=4096,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 6 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=65536,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=32768,operands=tensor}` | 6 | 0 | cpu | cpu | - |
| `amin{numel=4096,out=4096}` | 6 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=4096,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=65536,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=131072,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=524288,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=65536,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=131072}` | 6 | 0 | cpu | cpu | - |
| `relu{numel=524288}` | 6 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=2048}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=256,rows=512}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=512}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=64,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `select_where{numel=4096}` | 4 | 0 | cpu | cpu | - |
| `abs{numel=65536}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=65536,operands=tensor}` | 3 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `amin{numel=65536,out=65536}` | 3 | 0 | cpu | cpu | - |
| `embedding{dim=8,tokens=4096,vocab=32}` | 3 | 0 | cpu | cpu | - |
| `embedding{dim=8,tokens=65536,vocab=32}` | 3 | 0 | cpu | cpu | - |
| `log{numel=4096}` | 3 | 0 | cpu | cpu | - |
| `log{numel=65536}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=4096,operands=scalar}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=4096}` | 3 | 0 | cpu | cpu | - |
| `select_where{numel=65536}` | 3 | 0 | cpu | cpu | - |
| `sub{broadcast=1,numel=4096,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `sub{broadcast=1,numel=65536,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `embedding{dim=512,tokens=256,vocab=32128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=512,tokens=64,vocab=32128}` | 1 | 0 | cpu | cpu | - |

