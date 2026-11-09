# unsloth/Llama-3.2-1B

- domain: llm, family: llama, size: 1B, params at full depth: 1235.8M
- canonical: meta-llama/Llama-3.2-1B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [16, 2], "scales": {"model.layers": 8.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=1,n=8192}` | 32 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=1,n=2048}` | 16 | 16,777,216 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=128256}` | 1 | 262,668,288 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=2048}` | 32 | 4,194,304 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=512}` | 32 | 1,048,576 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=64}` | 16 | 526,336 | cpu | cpu | - |
| `bmm{b=32,k=64,m=1,n=257}` | 16 | 526,336 | cpu | cpu | - |
| `add{broadcast=0,numel=2048,operands=tensor}` | 48 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=2048,tokens=1}` | 33 | 0 | cpu | cpu | - |
| `concat{numel=131584}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=512,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=512,operands=tensor}` | 16 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=8224,operands=tensor}` | 16 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=2048}` | 16 | 0 | cpu | cpu | - |
| `concat{numel=512}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=8192,operands=tensor}` | 16 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 16 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1024}` | 16 | 0 | cpu | cpu | - |
| `neg{numel=256}` | 16 | 0 | cpu | cpu | - |
| `silu{numel=8192}` | 16 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=32}` | 16 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=64,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=64}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=64}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=1,vocab=128256}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=64}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=256,n=8192}` | 32 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=256,n=2048}` | 16 | 4,294,967,296 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=128256}` | 1 | 67,243,081,728 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=2048}` | 32 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=512}` | 32 | 268,435,456 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=64}` | 16 | 134,217,728 | cpu | cpu | - |
| `bmm{b=32,k=64,m=256,n=256}` | 16 | 134,217,728 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 48 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `rmsnorm{channels=2048,tokens=256}` | 33 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=131072,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=131072,operands=tensor}` | 16 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 16 | 0 | cpu | cpu | - |
| `concat{numel=131072}` | 16 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 16 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=tensor}` | 16 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 16 | 0 | cpu | cpu | - |
| `neg{numel=65536}` | 16 | 0 | cpu | cpu | - |
| `silu{numel=2097152}` | 16 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 16 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=16384,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=256,vocab=128256}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

