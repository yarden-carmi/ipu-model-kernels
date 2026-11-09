# vgg16.tv_in1k

- domain: vision-cnn, family: vgg, size: 138M, params at full depth: 138.4M
- canonical: vgg16.tv_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=1,cin=256,cout=256,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=802816,padding=1,stride=1,w=56}` | 2 | 1,849,688,064 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=401408,padding=1,stride=1,w=28}` | 2 | 1,849,688,064 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=128,dilation=1,groups=1,h=112,kh=3,kw=3,out_elements=1605632,padding=1,stride=1,w=112}` | 1 | 1,849,688,064 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=64,cout=64,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=3211264,padding=1,stride=1,w=224}` | 1 | 1,849,688,064 | cpu | cpu | - |
| `conv2d{bias=1,cin=512,cout=512,dilation=1,groups=1,h=14,kh=3,kw=3,out_elements=100352,padding=1,stride=1,w=14}` | 3 | 462,422,016 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=128,cout=256,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=802816,padding=1,stride=1,w=56}` | 1 | 924,844,032 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=256,cout=512,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=401408,padding=1,stride=1,w=28}` | 1 | 924,844,032 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=64,cout=128,dilation=1,groups=1,h=112,kh=3,kw=3,out_elements=1605632,padding=1,stride=1,w=112}` | 1 | 924,844,032 | chip-emu | chip-emu | conv_universal_bias (chip-emu, exact, fp32-exact) |
| `conv2d{bias=1,cin=512,cout=4096,dilation=1,groups=1,h=7,kh=7,kw=7,out_elements=4096,padding=0,stride=1,w=7}` | 1 | 102,760,448 | cpu | cpu | - |
| `conv2d{bias=1,cin=3,cout=64,dilation=1,groups=1,h=224,kh=3,kw=3,out_elements=3211264,padding=1,stride=1,w=224}` | 1 | 86,704,128 | cpu | cpu | - |
| `conv2d{bias=1,cin=4096,cout=4096,dilation=1,groups=1,h=1,kh=1,kw=1,out_elements=4096,padding=0,stride=1,w=1}` | 1 | 16,777,216 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=4096,m=1,n=1000}` | 1 | 4,096,000 | cpu | cpu | - |
| `relu{numel=100352}` | 3 | 0 | cpu | cpu | - |
| `relu{numel=401408}` | 3 | 0 | cpu | cpu | - |
| `relu{numel=802816}` | 3 | 0 | cpu | cpu | - |
| `relu{numel=1605632}` | 2 | 0 | cpu | cpu | - |
| `relu{numel=3211264}` | 2 | 0 | cpu | cpu | - |
| `relu{numel=4096}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=4096,h=1,out=1,w=1}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=4096,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=128,h=112,k=2,padding=0,stride=2,w=112}` | 1 | 0 | chip-emu | chip-emu | maxpool2d_stride2_tail (chip-emu, exact, fp32-exact) |
| `maxpool2d{channels=256,h=56,k=2,padding=0,stride=2,w=56}` | 1 | 0 | chip-emu | chip-emu | maxpool2d_stride2_tail (chip-emu, exact, fp32-exact) |
| `maxpool2d{channels=512,h=14,k=2,padding=0,stride=2,w=14}` | 1 | 0 | chip-emu | chip-emu | maxpool2d_stride2_tail (chip-emu, exact, fp32-exact) |
| `maxpool2d{channels=512,h=28,k=2,padding=0,stride=2,w=28}` | 1 | 0 | chip-emu | chip-emu | maxpool2d_stride2_tail (chip-emu, exact, fp32-exact) |
| `maxpool2d{channels=64,h=224,k=2,padding=0,stride=2,w=224}` | 1 | 0 | chip-emu | chip-emu | maxpool2d_stride2 (chip-emu, exact, fp32-exact) |

