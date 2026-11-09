# facebook/bart-base

- domain: seq2seq, family: bart, size: 140M, params at full depth: 139.4M
- canonical: facebook/bart-base
- depth scaling: `{"_scales_from": [1, 1], "decoder_layers": [6, 2], "num_hidden_layers": [6, 2], "scales": {"model.decoder.layers": 3.0, "model.encoder.layers": 3.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=768,m=256,n=768}` | 36 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=256,n=768}` | 6 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 6 | 603,979,776 | cpu | cpu | - |
| `linear{bias=0,k=768,m=64,n=50265}` | 1 | 2,470,625,280 | cpu | cpu | - |
| `linear{bias=1,k=768,m=64,n=768}` | 36 | 37,748,736 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=64,n=768}` | 6 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=768,m=64,n=3072}` | 6 | 150,994,944 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 6 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 6 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=256,m=64,n=64}` | 6 | 12,582,912 | cpu | cpu | - |
| `bmm{b=12,k=64,m=64,n=256}` | 6 | 12,582,912 | cpu | cpu | - |
| `bmm{b=12,k=64,m=64,n=64}` | 12 | 3,145,728 | chip-emu | chip-emu | matmul_64x64x64 (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=49152,operands=tensor}` | 19 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=768,layout=channels_last,tokens=64}` | 19 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=196608,operands=tensor}` | 13 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 13 | 0 | cpu | cpu | - |
| `concat{numel=196608}` | 12 | 0 | cpu | cpu | - |
| `concat{numel=49152}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=196608,operands=scalar}` | 7 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=49152,operands=scalar}` | 7 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=49152,operands=tensor}` | 6 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu{numel=196608}` | 6 | 0 | cpu | cpu | - |
| `gelu{numel=786432}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=256,rows=768}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=64,rows=768}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=64,operands=scalar}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 1 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=3216960,operands=tensor}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=1026}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=50265}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=64,vocab=1026}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=64,vocab=50265}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=64}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=4096}` | 1 | 0 | cpu | cpu | - |

