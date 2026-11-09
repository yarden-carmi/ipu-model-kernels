# sentence-transformers/all-MiniLM-L6-v2

- domain: nlp-encoder, family: bert, size: 22M, params at full depth: 22.7M
- canonical: sentence-transformers/all-MiniLM-L6-v2
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [6, 2], "scales": {"encoder.layer": 3.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=256,n=384}` | 6 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=384,m=256,n=1536}` | 6 | 150,994,944 | cpu | cpu | - |
| `linear{bias=1,k=384,m=256,n=384}` | 24 | 37,748,736 | cpu | cpu | - |
| `bmm{b=12,k=256,m=256,n=32}` | 6 | 25,165,824 | cpu | cpu | - |
| `bmm{b=12,k=32,m=256,n=256}` | 6 | 25,165,824 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1,n=384}` | 1 | 147,456 | cpu | cpu | - |
| `add{broadcast=0,numel=98304,operands=tensor}` | 14 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=384,layout=channels_last,tokens=256}` | 13 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `gelu{numel=393216}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=786432,operands=scalar}` | 6 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=3072}` | 6 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `embedding{dim=384,tokens=256,vocab=2}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=384,tokens=256,vocab=30522}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=384,tokens=256,vocab=512}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=256}` | 1 | 0 | cpu | cpu | - |
| `tanh{numel=384}` | 1 | 0 | cpu | cpu | - |

