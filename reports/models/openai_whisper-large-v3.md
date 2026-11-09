# openai/whisper-large-v3

- domain: audio, family: whisper, size: 1.55B, params at full depth: 1543.5M
- canonical: openai/whisper-large-v3
- depth scaling: `{"_scales_from": [1, 1], "decoder_layers": [32, 2], "num_hidden_layers": [32, 2], "scales": {"model.decoder.layers": 16.0, "model.encoder.layers": 16.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1280,m=1500,n=1280}` | 128 | 2,457,600,000 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=1500,n=5120}` | 32 | 9,830,400,000 | cpu | cpu | - |
| `linear{bias=1,k=5120,m=1500,n=1280}` | 32 | 9,830,400,000 | cpu | cpu | - |
| `linear{bias=0,k=1280,m=1500,n=1280}` | 64 | 2,457,600,000 | cpu | cpu | - |
| `bmm{b=20,k=1500,m=1500,n=64}` | 32 | 2,880,000,000 | cpu | cpu | - |
| `bmm{b=20,k=64,m=1500,n=1500}` | 32 | 2,880,000,000 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=32,n=1280}` | 160 | 52,428,800 | cpu | cpu | - |
| `conv1d{bias=1,cin=1280,cout=1280,dilation=1,groups=1,k=3,length=3000,out_elements=1920000,padding=1,stride=2}` | 1 | 7,372,800,000 | cpu | cpu | - |
| `linear{bias=1,k=1280,m=32,n=5120}` | 32 | 209,715,200 | cpu | cpu | - |
| `linear{bias=1,k=5120,m=32,n=1280}` | 32 | 209,715,200 | cpu | cpu | - |
| `linear{bias=0,k=1280,m=32,n=51866}` | 1 | 2,124,431,360 | cpu | cpu | - |
| `bmm{b=20,k=1500,m=32,n=64}` | 32 | 61,440,000 | cpu | cpu | - |
| `bmm{b=20,k=64,m=32,n=1500}` | 32 | 61,440,000 | cpu | cpu | - |
| `linear{bias=0,k=1280,m=32,n=1280}` | 32 | 52,428,800 | cpu | cpu | - |
| `conv1d{bias=1,cin=128,cout=1280,dilation=1,groups=1,k=3,length=3000,out_elements=3840000,padding=1,stride=1}` | 1 | 1,474,560,000 | cpu | cpu | - |
| `bmm{b=20,k=32,m=32,n=64}` | 32 | 1,310,720 | cpu | cpu | - |
| `bmm{b=20,k=64,m=32,n=32}` | 32 | 1,310,720 | cpu | cpu | - |
| `add{broadcast=0,numel=40960,operands=tensor}` | 97 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=1280,layout=channels_last,tokens=32}` | 97 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1920000,operands=tensor}` | 65 | 0 | cpu | cpu | - |
| `layernorm{channels=1280,layout=channels_last,tokens=1500}` | 65 | 0 | cpu | cpu | - |
| `concat{numel=1920000}` | 64 | 0 | cpu | cpu | - |
| `concat{numel=40960}` | 64 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=40960,operands=scalar}` | 64 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=20480,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `gelu{numel=163840}` | 32 | 0 | cpu | cpu | - |
| `gelu{numel=7680000}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=1920000,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=20480,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=45000000,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=960000,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=1500,rows=30000}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=1500,rows=640}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=32,rows=640}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=32,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `embedding{dim=1280,tokens=1500,vocab=1500}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=1280,tokens=32,vocab=51866}` | 1 | 0 | cpu | cpu | - |
| `gather{numel=40960}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=1920000}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=3840000}` | 1 | 0 | cpu | cpu | - |
| `repeat{numel=32}` | 1 | 0 | cpu | cpu | - |
| `select_where{numel=1024}` | 1 | 0 | cpu | cpu | - |

