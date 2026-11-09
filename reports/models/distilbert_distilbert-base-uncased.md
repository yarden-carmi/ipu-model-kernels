# distilbert/distilbert-base-uncased

- domain: nlp-encoder, family: distilbert, size: 66M, params at full depth: 67.0M
- canonical: distilbert/distilbert-base-uncased
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [6, 2], "scales": {"distilbert.transformer.layer": 3.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=768,m=256,n=30522}` | 1 | 6,000,869,376 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=768}` | 25 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=256,n=768}` | 6 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 6 | 603,979,776 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 6 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 6 | 50,331,648 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 14 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `add{broadcast=0,numel=196608,operands=tensor}` | 13 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu{numel=786432}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `embedding{dim=768,tokens=256,vocab=30522}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=512}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=196608}` | 1 | 0 | cpu | cpu | - |

