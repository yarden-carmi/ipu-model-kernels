# Qwen/Qwen1.5-MoE-A2.7B

- domain: llm, family: qwen2-moe, size: 14B-A2.7B, params at full depth: 14315.8M
- canonical: Qwen/Qwen1.5-MoE-A2.7B
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [24, 2], "scales": {"model.layers": 12.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=1,n=5632}` | 48 | 11,534,336 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=151936}` | 1 | 311,164,928 | cpu | cpu | - |
| `linear{bias=1,k=2048,m=1,n=2048}` | 72 | 4,194,304 | cpu | cpu | - |
| `linear{bias=0,k=5632,m=1,n=2048}` | 24 | 11,534,336 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=2048}` | 24 | 4,194,304 | cpu | cpu | - |
| `bmm{b=16,k=128,m=1,n=257}` | 24 | 526,336 | cpu | cpu | - |
| `bmm{b=16,k=257,m=1,n=128}` | 24 | 526,336 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=60}` | 24 | 122,880 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=1,n=1}` | 24 | 2,048 | cpu | cpu | - |
| `add{broadcast=0,numel=2048,operands=tensor}` | 120 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `mul{broadcast=1,numel=2048,operands=tensor}` | 120 | 0 | cpu | cpu | - |
| `rmsnorm{channels=2048,tokens=1}` | 49 | 0 | cpu | cpu | - |
| `concat{numel=2048}` | 48 | 0 | cpu | cpu | - |
| `concat{numel=526336}` | 48 | 0 | cpu | cpu | - |
| `gather{numel=8192}` | 48 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=5632,operands=tensor}` | 48 | 0 | cpu | cpu | - |
| `neg{numel=1024}` | 48 | 0 | cpu | cpu | - |
| `silu{numel=5632}` | 48 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `add{broadcast=1,numel=4112,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `aten{numel=11264,schema=aten::_grouped_mm}` | 24 | 0 | cpu | cpu | - |
| `aten{numel=8192,schema=aten::_grouped_mm}` | 24 | 0 | cpu | cpu | - |
| `cumsum{numel=60,out=60}` | 24 | 0 | cpu | cpu | - |
| `gather{numel=4}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=4112,operands=scalar}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=8192,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `sigmoid{numel=1}` | 24 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=257,rows=16}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=60,rows=1}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `sort{numel=4,out=4}` | 24 | 0 | cpu | cpu | - |
| `sum{numel=8192,out=2048}` | 24 | 0 | cpu | cpu | - |
| `topk{numel=60,out=4}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=257,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `select_where{numel=257}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=128}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=128}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=1,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=64,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=128}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=2048,m=256,n=5632}` | 48 | 2,952,790,016 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=151936}` | 1 | 79,658,221,568 | cpu | cpu | - |
| `linear{bias=1,k=2048,m=256,n=2048}` | 72 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=0,k=5632,m=256,n=2048}` | 24 | 2,952,790,016 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=2048}` | 24 | 1,073,741,824 | cpu | cpu | - |
| `bmm{b=16,k=128,m=256,n=256}` | 24 | 134,217,728 | cpu | cpu | - |
| `bmm{b=16,k=256,m=256,n=128}` | 24 | 134,217,728 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=60}` | 24 | 31,457,280 | cpu | cpu | - |
| `linear{bias=0,k=2048,m=256,n=1}` | 24 | 524,288 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 120 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=524288,operands=tensor}` | 120 | 0 | cpu | cpu | - |
| `rmsnorm{channels=2048,tokens=256}` | 49 | 0 | cpu | cpu | - |
| `concat{numel=524288}` | 48 | 0 | cpu | cpu | - |
| `gather{numel=2097152}` | 48 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1441792,operands=tensor}` | 48 | 0 | cpu | cpu | - |
| `neg{numel=262144}` | 48 | 0 | cpu | cpu | - |
| `silu{numel=1441792}` | 48 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=1048576,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `aten{numel=2097152,schema=aten::_grouped_mm}` | 24 | 0 | cpu | cpu | - |
| `aten{numel=2883584,schema=aten::_grouped_mm}` | 24 | 0 | cpu | cpu | - |
| `cumsum{numel=60,out=60}` | 24 | 0 | cpu | cpu | - |
| `gather{numel=1024}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1048576,operands=scalar}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=2097152,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `sigmoid{numel=256}` | 24 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=4096}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=60,rows=256}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `sort{numel=1024,out=1024}` | 24 | 0 | cpu | cpu | - |
| `sum{numel=2097152,out=524288}` | 24 | 0 | cpu | cpu | - |
| `topk{numel=15360,out=1024}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=256,operands=scalar}` | 5 | 0 | cpu | cpu | - |
| `aten{numel=256,schema=aten::diff}` | 2 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=32768,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `select_where{numel=65536}` | 2 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2048,tokens=256,vocab=151936}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16384,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32768}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | cpu | cpu | - |

