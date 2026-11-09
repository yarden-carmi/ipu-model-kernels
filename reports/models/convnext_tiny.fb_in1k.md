# convnext_tiny.fb_in1k

- domain: vision-cnn, family: convnext, size: 28.6M, params at full depth: 28.6M
- canonical: convnext_tiny.fb_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=1536,m=196,n=384}` | 9 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=384,m=196,n=1536}` | 9 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=192,m=784,n=768}` | 3 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=3072,m=49,n=768}` | 3 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=384,m=3136,n=96}` | 3 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=768,m=49,n=3072}` | 3 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=768,m=784,n=192}` | 3 | 115,605,504 | cpu | cpu | - |
| `linear{bias=1,k=96,m=3136,n=384}` | 3 | 115,605,504 | cpu | cpu | - |
| `conv2d{bias=1,cin=192,cout=384,dilation=1,groups=1,h=28,kh=2,kw=2,out_elements=75264,padding=0,stride=2,w=28}` | 1 | 57,802,752 | cpu | cpu | - |
| `conv2d{bias=1,cin=384,cout=768,dilation=1,groups=1,h=14,kh=2,kw=2,out_elements=37632,padding=0,stride=2,w=14}` | 1 | 57,802,752 | cpu | cpu | - |
| `conv2d{bias=1,cin=96,cout=192,dilation=1,groups=1,h=56,kh=2,kw=2,out_elements=150528,padding=0,stride=2,w=56}` | 1 | 57,802,752 | cpu | cpu | - |
| `conv2d{bias=1,cin=96,cout=96,dilation=1,groups=96,h=56,kh=7,kw=7,out_elements=301056,padding=3,stride=1,w=56}` | 3 | 14,751,744 | cpu | cpu | - |
| `conv2d{bias=1,cin=384,cout=384,dilation=1,groups=384,h=14,kh=7,kw=7,out_elements=75264,padding=3,stride=1,w=14}` | 9 | 3,687,936 | cpu | cpu | - |
| `conv2d{bias=1,cin=192,cout=192,dilation=1,groups=192,h=28,kh=7,kw=7,out_elements=150528,padding=3,stride=1,w=28}` | 3 | 7,375,872 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=96,dilation=1,groups=1,h=224,kh=4,kw=4,out_elements=301056,padding=0,stride=4,w=224}` | 1 | 14,450,688 | cpu | cpu | - |
| `conv2d{bias=1,cin=768,cout=768,dilation=1,groups=768,h=7,kh=7,kw=7,out_elements=37632,padding=3,stride=1,w=7}` | 3 | 1,843,968 | cpu | cpu | - |
| `linear{bias=1,k=768,m=1,n=1000}` | 1 | 768,000 | cpu | cpu | - |
| `add{broadcast=0,numel=75264,operands=tensor}` | 9 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `gelu{numel=301056}` | 9 | 0 | cpu | cpu | - |
| `layernorm{channels=384,layout=channels_last,tokens=196}` | 9 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=75264,operands=tensor}` | 9 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=150528,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=301056,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=37632,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `gelu{numel=1204224}` | 3 | 0 | cpu | cpu | - |
| `gelu{numel=150528}` | 3 | 0 | cpu | cpu | - |
| `gelu{numel=602112}` | 3 | 0 | cpu | cpu | - |
| `layernorm{channels=192,layout=channels_last,tokens=784}` | 3 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_last,tokens=49}` | 3 | 0 | cpu | cpu | - |
| `layernorm{channels=96,layout=channels_last,tokens=3136}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=150528,operands=tensor}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=301056,operands=tensor}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=1,numel=37632,operands=tensor}` | 3 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `layernorm{channels=96,layout=channels_first,tokens=3136}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=768,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=768,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=192,layout=channels_first,tokens=784}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=384,layout=channels_first,tokens=196}` | 1 | 0 | cpu | cpu | - |
| `layernorm{channels=768,layout=channels_first,tokens=1}` | 1 | 0 | cpu | cpu | - |

