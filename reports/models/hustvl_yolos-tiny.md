# hustvl/yolos-tiny

- domain: vision-detection, family: yolos, size: 6.5M, params at full depth: 6.5M
- canonical: hustvl/yolos-tiny
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [12, 2], "scales": {"vit.encoder.layer": 6.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `bmm{b=3,k=1829,m=1829,n=64}` | 12 | 642,286,272 | cpu | cpu | - |
| `bmm{b=3,k=64,m=1829,n=1829}` | 12 | 642,286,272 | cpu | cpu | - |
| `linear{bias=1,k=192,m=1829,n=192}` | 48 | 67,424,256 | cpu | cpu | - |
| `linear{bias=1,k=192,m=1829,n=768}` | 12 | 269,697,024 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1829,n=192}` | 12 | 269,697,024 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=192,dilation=1,groups=1,h=512,kh=16,kw=16,out_elements=331776,padding=0,stride=16,w=864}` | 1 | 254,803,968 | cpu | cpu | - |
| `linear{bias=1,k=192,m=100,n=192}` | 4 | 3,686,400 | cpu | cpu | - |
| `linear{bias=1,k=192,m=100,n=92}` | 1 | 1,766,400 | cpu | cpu | - |
| `linear{bias=1,k=192,m=100,n=4}` | 1 | 76,800 | cpu | cpu | - |
| `add{broadcast=0,numel=351168,operands=tensor}` | 25 | 0 | cpu | cpu | - |
| `layernorm{channels=192,layout=channels_last,tokens=1829}` | 25 | 0 | cpu | cpu | - |
| `gelu{numel=1404672}` | 12 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=10035723,operands=scalar}` | 12 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=1829,rows=5487}` | 12 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `relu{numel=19200}` | 4 | 0 | cpu | cpu | - |
| `aten{numel=331776,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=351168}` | 2 | 0 | cpu | cpu | - |
| `sigmoid{numel=400}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=192,h=50,mode=bicubic2d,out_elements=331776,w=83}` | 1 | 0 | cpu | cpu | - |

