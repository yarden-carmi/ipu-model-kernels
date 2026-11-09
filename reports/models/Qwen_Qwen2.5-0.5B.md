# Qwen/Qwen2.5-0.5B

- domain: llm, family: qwen2, size: 0.5B, params at full depth: 494.0M
- canonical: Qwen/Qwen2.5-0.5B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [24, 2], "scales": {"model.layers": 12.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=896,m=1,n=4864}` | 48 | 4,358,144 | cpu | cpu | - |
| `linear{bias=0,k=896,m=1,n=151936}` | 1 | 136,134,656 | cpu | cpu | - |
| `linear{bias=0,k=4864,m=1,n=896}` | 24 | 4,358,144 | cpu | cpu | - |
| `linear{bias=0,k=896,m=1,n=896}` | 24 | 802,816 | cpu | cpu | - |
| `linear{bias=1,k=896,m=1,n=896}` | 24 | 802,816 | cpu | cpu | - |
| `bmm{b=14,k=257,m=1,n=64}` | 24 | 230,272 | cpu | cpu | - |
| `bmm{b=14,k=64,m=1,n=257}` | 24 | 230,272 | cpu | cpu | - |
| `linear{bias=1,k=896,m=1,n=128}` | 48 | 114,688 | cpu | cpu | - |
| `add{broadcast=0,numel=896,operands=tensor}` | 72 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=896,tokens=1}` | 49 | 0 | cpu | cpu | - |
| `concat{numel=32896}` | 48 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=128,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=896,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=128,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=3598,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=128}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=896}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=3598,operands=scalar}` | 24 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=4864,operands=tensor}` | 24 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=448}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=64}` | 24 | 0 | cpu | cpu | - |
| `silu{numel=4864}` | 24 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=14}` | 24 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=64,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=64}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=64}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=896,tokens=1,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=32,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=64}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=896,m=256,n=4864}` | 48 | 1,115,684,864 | cpu | cpu | - |
| `linear{bias=0,k=896,m=256,n=151936}` | 1 | 34,850,471,936 | cpu | cpu | - |
| `linear{bias=0,k=4864,m=256,n=896}` | 24 | 1,115,684,864 | cpu | cpu | - |
| `linear{bias=0,k=896,m=256,n=896}` | 24 | 205,520,896 | cpu | cpu | - |
| `linear{bias=1,k=896,m=256,n=896}` | 24 | 205,520,896 | cpu | cpu | - |
| `bmm{b=14,k=256,m=256,n=64}` | 24 | 58,720,256 | cpu | cpu | - |
| `bmm{b=14,k=64,m=256,n=256}` | 24 | 58,720,256 | cpu | cpu | - |
| `linear{bias=1,k=896,m=256,n=128}` | 48 | 29,360,128 | cpu | cpu | - |
| `add{broadcast=0,numel=229376,operands=tensor}` | 72 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `rmsnorm{channels=896,tokens=256}` | 49 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=229376,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=32768,operands=tensor}` | 48 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=32768,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=917504,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=229376}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1245184,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=917504,operands=scalar}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=114688}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=16384}` | 24 | 0 | cpu | cpu | - |
| `silu{numel=1245184}` | 24 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3584}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=16384,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=896,tokens=256,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=16384}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

