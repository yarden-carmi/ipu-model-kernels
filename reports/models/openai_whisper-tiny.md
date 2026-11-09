# openai/whisper-tiny

- domain: audio, family: whisper, size: 39M, params at full depth: 37.8M
- canonical: openai/whisper-tiny
- depth scaling: `{"_scales_from": [1, 1], "decoder_layers": [4, 2], "num_hidden_layers": [4, 2], "scales": {"model.decoder.layers": 2.0, "model.encoder.layers": 2.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=1500,n=384}` | 4 | 884,736,000 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1500,n=1536}` | 4 | 884,736,000 | cpu | cpu | - |
| `linear{bias=1,k=384,m=1500,n=384}` | 16 | 221,184,000 | cpu | cpu | - |
| `bmm{b=6,k=1500,m=1500,n=64}` | 4 | 864,000,000 | cpu | cpu | - |
| `bmm{b=6,k=64,m=1500,n=1500}` | 4 | 864,000,000 | cpu | cpu | - |
| `linear{bias=0,k=384,m=1500,n=384}` | 8 | 221,184,000 | cpu | cpu | - |
| `conv1d{bias=1,cin=384,cout=384,dilation=1,groups=1,k=3,length=3000,out_elements=576000,padding=1,stride=2}` | 1 | 663,552,000 | cpu | cpu | - |
| `linear{bias=0,k=384,m=32,n=51865}` | 1 | 637,317,120 | cpu | cpu | - |
| `conv1d{bias=1,cin=80,cout=384,dilation=1,groups=1,k=3,length=3000,out_elements=1152000,padding=1,stride=1}` | 1 | 276,480,000 | cpu | cpu | - |
| `linear{bias=1,k=384,m=32,n=384}` | 20 | 4,718,592 | cpu | cpu | - |
| `linear{bias=1,k=1536,m=32,n=384}` | 4 | 18,874,368 | cpu | cpu | - |
| `linear{bias=1,k=384,m=32,n=1536}` | 4 | 18,874,368 | cpu | cpu | - |
| `bmm{b=6,k=1500,m=32,n=64}` | 4 | 18,432,000 | cpu | cpu | - |
| `bmm{b=6,k=64,m=32,n=1500}` | 4 | 18,432,000 | cpu | cpu | - |
| `linear{bias=0,k=384,m=32,n=384}` | 4 | 4,718,592 | cpu | cpu | - |
| `bmm{b=6,k=32,m=32,n=64}` | 4 | 393,216 | cpu | cpu | - |
| `bmm{b=6,k=64,m=32,n=32}` | 4 | 393,216 | cpu | cpu | - |
| `add{broadcast=0,numel=12288,operands=tensor}` | 13 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=384,layout=channels_last,tokens=32}` | 13 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=576000,operands=tensor}` | 9 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `layernorm{channels=384,layout=channels_last,tokens=1500}` | 9 | 0 | cpu | cpu | - |
| `concat{numel=12288}` | 8 | 0 | cpu | cpu | - |
| `concat{numel=576000}` | 8 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=12288,operands=scalar}` | 8 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=1,numel=6144,operands=tensor}` | 4 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `gelu{numel=2304000}` | 4 | 0 | cpu | cpu | - |
| `gelu{numel=49152}` | 4 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=13500000,operands=scalar}` | 4 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=288000,operands=scalar}` | 4 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=576000,operands=scalar}` | 4 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=6144,operands=scalar}` | 4 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=1500,rows=192}` | 4 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=1500,rows=9000}` | 4 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=32,rows=192}` | 4 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=32,operands=scalar}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `embedding{dim=384,tokens=1500,vocab=1500}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=384,tokens=32,vocab=51865}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=12288}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=1152000}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=576000}` | 1 | 0 | cpu | cpu | - |
| `repeat{numel=32}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=1024}` | 1 | 0 | cpu | cpu | - |

