# FacebookAI/roberta-large

- domain: nlp-encoder, family: roberta, size: 355M, params at full depth: 355.4M
- canonical: FacebookAI/roberta-large
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [24, 2], "scales": {"roberta.encoder.layer": 12.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1024,m=256,n=1024}` | 97 | 268,435,456 | cpu | cpu | - |
| `linear{bias=1,k=1024,m=256,n=4096}` | 24 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=1,k=4096,m=256,n=1024}` | 24 | 1,073,741,824 | cpu | cpu | - |
| `linear{bias=1,k=1024,m=256,n=50265}` | 1 | 13,176,668,160 | cpu | cpu | - |
| `bmm{b=16,k=256,m=256,n=64}` | 24 | 67,108,864 | cpu | cpu | - |
| `bmm{b=16,k=64,m=256,n=256}` | 24 | 67,108,864 | cpu | cpu | - |
| `add{broadcast=0,numel=262144,operands=tensor}` | 50 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=1024,layout=channels_last,tokens=256}` | 50 | 0 | chip-emu | cpu | layernorm_rsqrt_nx8 (chip-emu, approximation, rsqrt_nx8) |
| `gelu{numel=1048576}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1048576,operands=scalar}` | 24 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=4096}` | 24 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::type_as}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1024,tokens=256,vocab=1}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1024,tokens=256,vocab=50265}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1024,tokens=256,vocab=514}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=256}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=262144}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |

