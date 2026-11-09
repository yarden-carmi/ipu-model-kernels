# unsloth/mistral-7b-v0.3

- domain: llm, family: mistral, size: 7B, params at full depth: 7248.0M
- canonical: mistralai/Mistral-7B-v0.3
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [32, 2], "scales": {"model.layers": 16.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=4096,m=1,n=14336}` | 64 | 58,720,256 | cpu | cpu | - |
| `linear{bias=0,k=14336,m=1,n=4096}` | 32 | 58,720,256 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=4096}` | 64 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=1024}` | 64 | 4,194,304 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=32768}` | 1 | 134,217,728 | cpu | cpu | - |
| `bmm{b=32,k=128,m=1,n=257}` | 32 | 1,052,672 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=128}` | 32 | 1,052,672 | cpu | cpu | - |
| `add{broadcast=0,numel=4096,operands=tensor}` | 96 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=4096,tokens=1}` | 65 | 0 | cpu | cpu | - |
| `concat{numel=263168}` | 64 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 64 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=4096,operands=tensor}` | 64 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=1024,operands=tensor}` | 32 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=8224,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=1024}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=4096}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=14336,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=2048}` | 32 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 32 | 0 | cpu | cpu | - |
| `silu{numel=14336}` | 32 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=32}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=4096,tokens=1,vocab=32768}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=4096,m=256,n=14336}` | 64 | 15,032,385,536 | cpu | cpu | - |
| `linear{bias=0,k=14336,m=256,n=4096}` | 32 | 15,032,385,536 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=4096}` | 64 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=1024}` | 64 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=32768}` | 1 | 34,359,738,368 | cpu | cpu | - |
| `bmm{b=32,k=128,m=256,n=256}` | 32 | 268,435,456 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=128}` | 32 | 268,435,456 | cpu | cpu | - |
| `add{broadcast=0,numel=1048576,operands=tensor}` | 96 | 0 | cpu | cpu | - |
| `rmsnorm{channels=4096,tokens=256}` | 65 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1048576,operands=tensor}` | 64 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 64 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=262144,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=1048576}` | 32 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3670016,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 32 | 0 | cpu | cpu | - |
| `neg{numel=524288}` | 32 | 0 | cpu | cpu | - |
| `silu{numel=3670016}` | 32 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=4096,tokens=256,vocab=32768}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

