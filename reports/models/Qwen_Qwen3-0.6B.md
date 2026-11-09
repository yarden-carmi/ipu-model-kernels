# Qwen/Qwen3-0.6B

- domain: llm, family: qwen3, size: 0.6B, params at full depth: 596.0M
- canonical: Qwen/Qwen3-0.6B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [28, 2], "scales": {"model.layers": 14.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=1024,m=1,n=3072}` | 56 | 3,145,728 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=1,n=151936}` | 1 | 155,582,464 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=1,n=1024}` | 28 | 3,145,728 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=1,n=1024}` | 56 | 1,048,576 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=1,n=2048}` | 28 | 2,097,152 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=1024}` | 28 | 2,097,152 | cpu | cpu | - |
| `bmm{b=16,k=128,m=1,n=257}` | 28 | 526,336 | cpu | cpu | - |
| `bmm{b=16,k=257,m=1,n=128}` | 28 | 526,336 | cpu | cpu | - |
| `add{broadcast=0,numel=1024,operands=tensor}` | 84 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=1024,tokens=1}` | 57 | 0 | cpu | cpu | - |
| `concat{numel=263168}` | 56 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=2048,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=4112,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=1024}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=2048}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3072,operands=tensor}` | 28 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=4112,operands=scalar}` | 28 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1024}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 28 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=16}` | 28 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=8}` | 28 | 0 | cpu | cpu | - |
| `silu{numel=3072}` | 28 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=16}` | 28 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1024,tokens=1,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=1024,m=256,n=3072}` | 56 | 805,306,368 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=256,n=151936}` | 1 | 39,829,110,784 | cpu | cpu | - |
| `linear{bias=0,k=3072,m=256,n=1024}` | 28 | 805,306,368 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=256,n=1024}` | 56 | 268,435,456 | cpu | cpu | - |
| `linear{bias=0,k=1024,m=256,n=2048}` | 28 | 536,870,912 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=1024}` | 28 | 536,870,912 | cpu | cpu | - |
| `bmm{b=16,k=128,m=256,n=256}` | 28 | 134,217,728 | cpu | cpu | - |
| `bmm{b=16,k=256,m=256,n=128}` | 28 | 134,217,728 | cpu | cpu | - |
| `add{broadcast=0,numel=262144,operands=tensor}` | 84 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `rmsnorm{channels=1024,tokens=256}` | 57 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=524288,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=1048576,operands=tensor}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1048576,operands=scalar}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=tensor}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 28 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=2048}` | 28 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=4096}` | 28 | 0 | cpu | cpu | - |
| `silu{numel=786432}` | 28 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=256,rows=4096}` | 28 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1024,tokens=256,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

