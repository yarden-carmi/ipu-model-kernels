# facebook/hubert-base-ls960

- domain: audio, family: hubert, size: 95M, params at full depth: 94.4M
- canonical: facebook/hubert-base-ls960
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"encoder.layers": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=3072,m=99,n=768}` | 12 | 233,570,304 | cpu | cpu | - |
| `linear{bias=1,k=768,m=99,n=3072}` | 12 | 233,570,304 | cpu | cpu | - |
| `linear{bias=1,k=768,m=99,n=768}` | 48 | 58,392,576 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=3,length=6399,out_elements=1637888,padding=0,stride=2}` | 1 | 2,515,795,968 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=3,length=3199,out_elements=818688,padding=0,stride=2}` | 1 | 1,257,504,768 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=3,length=1599,out_elements=409088,padding=0,stride=2}` | 1 | 628,359,168 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=3,length=799,out_elements=204288,padding=0,stride=2}` | 1 | 313,786,368 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=2,length=399,out_elements=101888,padding=0,stride=2}` | 1 | 104,333,312 | cpu | cpu | - |
| `bmm{b=12,k=64,m=99,n=99}` | 12 | 7,527,168 | cpu | cpu | - |
| `bmm{b=12,k=99,m=99,n=64}` | 12 | 7,527,168 | cpu | cpu | - |
| `conv1d{bias=0,cin=512,cout=512,dilation=1,groups=1,k=2,length=199,out_elements=50688,padding=0,stride=2}` | 1 | 51,904,512 | cpu | cpu | - |
| `linear{bias=1,k=512,m=99,n=768}` | 1 | 38,928,384 | cpu | cpu | - |
| `conv1d{bias=0,cin=1,cout=512,dilation=1,groups=1,k=10,length=32000,out_elements=3276288,padding=0,stride=5}` | 1 | 32,762,880 | cpu | cpu | - |
| `add{broadcast=0,numel=76032,operands=tensor}` | 25 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=768,layout=channels_last,tokens=99}` | 25 | 0 | cpu | cpu | - |
| `gelu{numel=304128}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=117612,operands=scalar}` | 12 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=99,rows=1188}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `aten{numel=4718592,schema=aten::_weight_norm}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=76800,schema=aten::conv1d}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=101888}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=1637888}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=204288}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=3276288}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=409088}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=50688}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=76032}` | 1 | 0 | cpu | cpu | - |
| `gelu{numel=818688}` | 1 | 0 | cpu | cpu | - |
| `groupnorm{channels=512,groups=512,hw=6399}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=512,layout=channels_last,tokens=99}` | 1 | 0 | cpu | cpu | - |

