# microsoft/deberta-v3-base

- domain: nlp-encoder, family: deberta-v2, size: 184M, params at full depth: 183.8M
- canonical: microsoft/deberta-v3-base
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"encoder.layer": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=256,n=768}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=768}` | 48 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=768,m=512,n=768}` | 24 | 301,989,888 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=512}` | 24 | 100,663,296 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 12 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 12 | 50,331,648 | cpu | cpu | - |
| `aten{numel=0,schema=aten::size.int}` | 60 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1,operands=scalar}` | 36 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sqrt{numel=1}` | 36 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=65536,operands=scalar}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 25 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=196608,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=786432,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `clamp{numel=65536}` | 24 | 0 | cpu | cpu | - |
| `div{broadcast=1,numel=786432,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `gather{numel=786432}` | 24 | 0 | cpu | cpu | - |
| `repeat{numel=393216}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=786432,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `div{broadcast=1,numel=196608,operands=tensor}` | 12 | 0 | cpu | cpu | - |
| `gelu{numel=786432}` | 12 | 0 | cpu | cpu | - |
| `neg{numel=65536}` | 12 | 0 | cpu | cpu | - |
| `select_where{numel=786432}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `select_where{numel=65536}` | 2 | 0 | cpu | cpu | - |
| `abs{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=1,schema=aten::type_as}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=65536,schema=aten::type_as}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=65536,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=1,numel=65536,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=128100}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=512}` | 1 | 0 | cpu | cpu | - |
| `log{numel=1}` | 1 | 0 | cpu | cpu | - |
| `log{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=65536,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=65536,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=196608,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=65536,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `sub{broadcast=1,numel=65536,operands=tensor}` | 1 | 0 | cpu | cpu | - |

