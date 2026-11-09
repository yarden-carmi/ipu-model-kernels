# Qwen/Qwen2.5-7B

- domain: llm, family: qwen2, size: 7B, params at full depth: 7615.6M
- canonical: Qwen/Qwen2.5-7B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [28, 2], "scales": {"model.layers": 14.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=3584,m=1,n=18944}` | 56 | 67,895,296 | cpu | cpu | - |
| `linear{bias=0,k=18944,m=1,n=3584}` | 28 | 67,895,296 | cpu | cpu | - |
| `linear{bias=0,k=3584,m=1,n=152064}` | 1 | 544,997,376 | cpu | cpu | - |
| `linear{bias=0,k=3584,m=1,n=3584}` | 28 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=3584,m=1,n=3584}` | 28 | 12,845,056 | cpu | cpu | - |
| `linear{bias=1,k=3584,m=1,n=512}` | 56 | 1,835,008 | cpu | cpu | - |
| `bmm{b=28,k=128,m=1,n=257}` | 28 | 921,088 | cpu | cpu | - |
| `bmm{b=28,k=257,m=1,n=128}` | 28 | 921,088 | cpu | cpu | - |
| `add{broadcast=0,numel=3584,operands=tensor}` | 84 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `rmsnorm{channels=3584,tokens=1}` | 57 | 0 | cpu | cpu | - |
| `concat{numel=131584}` | 56 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=3584,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=512,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=512,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=7196,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=3584}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=512}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=18944,operands=tensor}` | 28 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=7196,operands=scalar}` | 28 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `neg{numel=1792}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=256}` | 28 | 0 | cpu | cpu | - |
| `silu{numel=18944}` | 28 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `softmax{dim_last=1,n=257,rows=28}` | 28 | 0 | chip-emu | chip-emu | softmax_exp2_nx8_e4 (chip-emu, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=3584,tokens=1,vocab=152064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=3584,m=256,n=18944}` | 56 | 17,381,195,776 | cpu | cpu | - |
| `linear{bias=0,k=18944,m=256,n=3584}` | 28 | 17,381,195,776 | cpu | cpu | - |
| `linear{bias=0,k=3584,m=256,n=152064}` | 1 | 139,519,328,256 | cpu | cpu | - |
| `linear{bias=0,k=3584,m=256,n=3584}` | 28 | 3,288,334,336 | cpu | cpu | - |
| `linear{bias=1,k=3584,m=256,n=3584}` | 28 | 3,288,334,336 | cpu | cpu | - |
| `linear{bias=1,k=3584,m=256,n=512}` | 56 | 469,762,048 | cpu | cpu | - |
| `bmm{b=28,k=128,m=256,n=256}` | 28 | 234,881,024 | cpu | cpu | - |
| `bmm{b=28,k=256,m=256,n=128}` | 28 | 234,881,024 | cpu | cpu | - |
| `add{broadcast=0,numel=917504,operands=tensor}` | 84 | 0 | cpu | cpu | - |
| `rmsnorm{channels=3584,tokens=256}` | 57 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=131072,operands=tensor}` | 56 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=917504,operands=tensor}` | 56 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=131072,operands=tensor}` | 28 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=1,numel=1835008,operands=tensor}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=131072}` | 28 | 0 | cpu | cpu | - |
| `concat{numel=917504}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1835008,operands=scalar}` | 28 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=4849664,operands=tensor}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=458752}` | 28 | 0 | cpu | cpu | - |
| `neg{numel=65536}` | 28 | 0 | cpu | cpu | - |
| `silu{numel=4849664}` | 28 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=7168}` | 28 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=3584,tokens=256,vocab=152064}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

