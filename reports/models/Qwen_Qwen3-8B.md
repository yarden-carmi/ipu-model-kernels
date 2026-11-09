# Qwen/Qwen3-8B

- domain: llm, family: qwen3, size: 8B, params at full depth: 8190.7M
- canonical: Qwen/Qwen3-8B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [36, 2], "scales": {"model.layers": 18.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=4096,m=1,n=12288}` | 72 | 50,331,648 | cpu | cpu | - |
| `linear{bias=0,k=12288,m=1,n=4096}` | 36 | 50,331,648 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=4096}` | 72 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=151936}` | 1 | 622,329,856 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=1,n=1024}` | 72 | 4,194,304 | cpu | cpu | - |
| `bmm{b=32,k=128,m=1,n=257}` | 36 | 1,052,672 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=128}` | 36 | 1,052,672 | cpu | cpu | - |
| `add{broadcast=0,numel=4096,operands=tensor}` | 108 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=4096,tokens=1}` | 73 | 0 | cpu | cpu | - |
| `concat{numel=263168}` | 72 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 72 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=4096,operands=tensor}` | 72 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1024,operands=tensor}` | 36 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=8224,operands=tensor}` | 36 | 0 | cpu | cpu | - |
| `concat{numel=1024}` | 36 | 0 | cpu | cpu | - |
| `concat{numel=4096}` | 36 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=12288,operands=tensor}` | 36 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 36 | 0 | cpu | cpu | - |
| `neg{numel=2048}` | 36 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 36 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=32}` | 36 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=8}` | 36 | 0 | cpu | cpu | - |
| `silu{numel=12288}` | 36 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=32}` | 36 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=4096,tokens=1,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=4096,m=256,n=12288}` | 72 | 12,884,901,888 | cpu | cpu | - |
| `linear{bias=0,k=12288,m=256,n=4096}` | 36 | 12,884,901,888 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=4096}` | 72 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=151936}` | 1 | 159,316,443,136 | cpu | cpu | - |
| `linear{bias=0,k=4096,m=256,n=1024}` | 72 | 1,073,741,824 | cpu | cpu | - |
| `bmm{b=32,k=128,m=256,n=256}` | 36 | 268,435,456 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=128}` | 36 | 268,435,456 | cpu | cpu | - |
| `add{broadcast=0,numel=1048576,operands=tensor}` | 108 | 0 | cpu | cpu | - |
| `rmsnorm{channels=4096,tokens=256}` | 73 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1048576,operands=tensor}` | 72 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 72 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=262144,operands=tensor}` | 36 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 36 | 0 | cpu | cpu | - |
| `concat{numel=1048576}` | 36 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 36 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 36 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3145728,operands=tensor}` | 36 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 36 | 0 | cpu | cpu | - |
| `neg{numel=524288}` | 36 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=2048}` | 36 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=8192}` | 36 | 0 | cpu | cpu | - |
| `silu{numel=3145728}` | 36 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 36 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=4096,tokens=256,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

