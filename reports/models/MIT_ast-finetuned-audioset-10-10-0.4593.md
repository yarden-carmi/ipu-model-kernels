# MIT/ast-finetuned-audioset-10-10-0.4593

- domain: audio, family: ast, size: 87M, params at full depth: 86.6M
- canonical: MIT/ast-finetuned-audioset-10-10-0.4593
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"audio_spectrogram_transformer.layers": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=1214,n=768}` | 12 | 2,864,185,344 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1214,n=3072}` | 12 | 2,864,185,344 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1214,n=768}` | 48 | 716,046,336 | cpu | cpu | - |
| `bmm{b=12,k=1214,m=1214,n=64}` | 12 | 1,131,875,328 | cpu | cpu | - |
| `bmm{b=12,k=64,m=1214,n=1214}` | 12 | 1,131,875,328 | cpu | cpu | - |
| `conv2d{bias=1,cin=1,cout=768,dilation=1,groups=1,h=128,kh=16,kw=16,out_elements=930816,padding=0,stride=10,w=1024}` | 1 | 238,288,896 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=527}` | 1 | 404,736 | cpu | cpu | - |
| `add{broadcast=0,numel=932352,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=1214}` | 25 | 0 | cpu | cpu | - |
| `gelu{numel=3729408}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=17685552,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=1214,rows=14568}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=768,operands=tensor}` | 1 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `aten{numel=930816,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=932352}` | 1 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=768,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=1}` | 1 | 0 | cpu | cpu | - |

