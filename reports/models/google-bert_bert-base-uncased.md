# google-bert/bert-base-uncased

- domain: nlp-encoder, family: bert, size: 110M, params at full depth: 109.5M
- canonical: google-bert/bert-base-uncased
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"bert.encoder.layer": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=768,m=256,n=768}` | 49 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=256,n=768}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=3072}` | 12 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=768,m=256,n=30522}` | 1 | 6,000,869,376 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=64}` | 12 | 50,331,648 | cpu | cpu | - |
| `bmm{b=12,k=64,m=256,n=256}` | 12 | 50,331,648 | cpu | cpu | - |
| `add{broadcast=0,numel=196608,operands=tensor}` | 26 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=768,layout=channels_last,tokens=256}` | 26 | 0 | cpu | cpu | - |
| `gelu{numel=786432}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `embedding{dim=768,tokens=256,vocab=2}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=30522}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=512}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=256}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=196608}` | 1 | 0 | cpu | cpu | - |

