# Qwen/Qwen2.5-72B

- domain: llm, family: qwen2, size: 72B, params at full depth: 72706.2M
- canonical: Qwen/Qwen2.5-72B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [80, 2], "scales": {"model.layers": 40.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=8192,m=1,n=29568}` | 160 | 242,221,056 | cpu | cpu | - |
| `linear{bias=0,k=29568,m=1,n=8192}` | 80 | 242,221,056 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=1,n=8192}` | 80 | 67,108,864 | cpu | cpu | - |
| `linear{bias=1,k=8192,m=1,n=8192}` | 80 | 67,108,864 | cpu | cpu | - |
| `linear{bias=1,k=8192,m=1,n=1024}` | 160 | 8,388,608 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=1,n=152064}` | 1 | 1,245,708,288 | cpu | cpu | - |
| `bmm{b=64,k=128,m=1,n=257}` | 80 | 2,105,344 | cpu | cpu | - |
| `bmm{b=64,k=257,m=1,n=128}` | 80 | 2,105,344 | cpu | cpu | - |
| `add{broadcast=0,numel=8192,operands=tensor}` | 240 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=8192,tokens=1}` | 161 | 0 | cpu | cpu | - |
| `concat{numel=263168}` | 160 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 160 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 160 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=1024,operands=tensor}` | 80 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=16448,operands=tensor}` | 80 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=1024}` | 80 | 0 | cpu | cpu | - |
| `concat{numel=8192}` | 80 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=16448,operands=scalar}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=29568,operands=tensor}` | 80 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=4096}` | 80 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 80 | 0 | cpu | cpu | - |
| `silu{numel=29568}` | 80 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=64}` | 80 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=8192,tokens=1,vocab=152064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=8192,m=256,n=29568}` | 160 | 62,008,590,336 | cpu | cpu | - |
| `linear{bias=0,k=29568,m=256,n=8192}` | 80 | 62,008,590,336 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=256,n=8192}` | 80 | 17,179,869,184 | cpu | cpu | - |
| `linear{bias=1,k=8192,m=256,n=8192}` | 80 | 17,179,869,184 | cpu | cpu | - |
| `linear{bias=1,k=8192,m=256,n=1024}` | 160 | 2,147,483,648 | cpu | cpu | - |
| `linear{bias=0,k=8192,m=256,n=152064}` | 1 | 318,901,321,728 | cpu | cpu | - |
| `bmm{b=64,k=128,m=256,n=256}` | 80 | 536,870,912 | cpu | cpu | - |
| `bmm{b=64,k=256,m=256,n=128}` | 80 | 536,870,912 | cpu | cpu | - |
| `add{broadcast=0,numel=2097152,operands=tensor}` | 240 | 0 | cpu | cpu | - |
| `rmsnorm{channels=8192,tokens=256}` | 161 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=2097152,operands=tensor}` | 160 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 160 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=262144,operands=tensor}` | 80 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=4194304,operands=tensor}` | 80 | 0 | cpu | cpu | - |
| `concat{numel=2097152}` | 80 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 80 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=4194304,operands=scalar}` | 80 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=7569408,operands=tensor}` | 80 | 0 | cpu | cpu | - |
| `neg{numel=1048576}` | 80 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 80 | 0 | cpu | cpu | - |
| `silu{numel=7569408}` | 80 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=16384}` | 80 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=8192,tokens=256,vocab=152064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

