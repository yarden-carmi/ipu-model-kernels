# facebook/detr-resnet-50

- domain: vision-detection, family: detr, size: 41M, params at full depth: 41.5M
- canonical: facebook/detr-resnet-50
- depth scaling: `{"_scales_from": [1, 1], "decoder_layers": [6, 2], "num_hidden_layers": [6, 2], "scales": {"model.decoder.layers": 3.0, "model.encoder.layers": 3.0}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=262144,padding=1,stride=1,w=32}` | 5 | 603,979,776 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=524288,padding=1,stride=1,w=64}` | 3 | 603,979,776 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=1,h=128,kh=3,kw=3,out_elements=1048576,padding=1,stride=1,w=128}` | 3 | 603,979,776 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=1024,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=32}` | 6 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=1024,cout=256,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=262144,padding=0,stride=1,w=32}` | 5 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=512,dilation=1,groups=1,h=16,kh=3,kw=3,out_elements=131072,padding=1,stride=1,w=16}` | 2 | 603,979,776 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=512,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=2097152,padding=0,stride=1,w=64}` | 4 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=256,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=4194304,padding=0,stride=1,w=128}` | 4 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=128,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=524288,padding=0,stride=1,w=64}` | 3 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=2048,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=524288,padding=0,stride=1,w=16}` | 3 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=2048,m=256,n=256}` | 6 | 134,217,728 | cpu | cpu | - |
| `linear{bias=1,k=256,m=256,n=2048}` | 6 | 134,217,728 | cpu | cpu | - |
| `conv2d{bias=0,cin=3,cout=64,dilation=1,groups=1,h=512,kh=7,kw=7,out_elements=4194304,padding=3,stride=2,w=512}` | 1 | 616,562,688 | cpu | cpu | - |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=128,kh=3,kw=3,out_elements=524288,padding=1,stride=2,w=128}` | 1 | 603,979,776 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=256,dilation=1,groups=1,h=64,kh=3,kw=3,out_elements=262144,padding=1,stride=2,w=64}` | 1 | 603,979,776 | cpu | cpu | - |
| `conv2d{bias=0,cin=512,cout=512,dilation=1,groups=1,h=32,kh=3,kw=3,out_elements=131072,padding=1,stride=2,w=32}` | 1 | 603,979,776 | cpu | cpu | - |
| `linear{bias=1,k=256,m=256,n=256}` | 36 | 16,777,216 | cpu | cpu | - |
| `conv2d{bias=0,cin=1024,cout=2048,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=524288,padding=0,stride=2,w=32}` | 1 | 536,870,912 | cpu | cpu | - |
| `conv2d{bias=0,cin=1024,cout=512,dilation=1,groups=1,h=32,kh=1,kw=1,out_elements=524288,padding=0,stride=1,w=32}` | 1 | 536,870,912 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=2048,cout=512,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=131072,padding=0,stride=1,w=16}` | 2 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=2097152,padding=0,stride=1,w=128}` | 1 | 536,870,912 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=512,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=2097152,padding=0,stride=2,w=128}` | 1 | 536,870,912 | cpu | cpu | - |
| `conv2d{bias=0,cin=256,cout=64,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=128}` | 2 | 268,435,456 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=1024,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1048576,padding=0,stride=2,w=64}` | 1 | 536,870,912 | cpu | cpu | - |
| `conv2d{bias=0,cin=512,cout=256,dilation=1,groups=1,h=64,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=64}` | 1 | 536,870,912 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=2048,m=100,n=256}` | 6 | 52,428,800 | cpu | cpu | - |
| `linear{bias=1,k=256,m=100,n=2048}` | 6 | 52,428,800 | cpu | cpu | - |
| `linear{bias=1,k=256,m=100,n=256}` | 38 | 6,553,600 | cpu | cpu | - |
| `conv2d{bias=1,cin=2048,cout=256,dilation=1,groups=1,h=16,kh=1,kw=1,out_elements=65536,padding=0,stride=1,w=16}` | 1 | 134,217,728 | chip-emu | chip-emu | pointwise_conv_unified_bias (chip-emu, exact, fp32-exact) |
| `bmm{b=8,k=256,m=256,n=32}` | 6 | 16,777,216 | cpu | cpu | - |
| `bmm{b=8,k=32,m=256,n=256}` | 6 | 16,777,216 | cpu | cpu | - |
| `conv2d{bias=0,cin=64,cout=64,dilation=1,groups=1,h=128,kh=1,kw=1,out_elements=1048576,padding=0,stride=1,w=128}` | 1 | 67,108,864 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `bmm{b=8,k=256,m=100,n=32}` | 6 | 6,553,600 | cpu | cpu | - |
| `bmm{b=8,k=32,m=100,n=256}` | 6 | 6,553,600 | cpu | cpu | - |
| `bmm{b=8,k=100,m=100,n=32}` | 6 | 2,560,000 | cpu | cpu | - |
| `bmm{b=8,k=32,m=100,n=100}` | 6 | 2,560,000 | cpu | cpu | - |
| `linear{bias=1,k=256,m=100,n=92}` | 1 | 2,355,200 | cpu | cpu | - |
| `linear{bias=1,k=256,m=100,n=4}` | 1 | 102,400 | cpu | cpu | - |
| `add{broadcast=0,numel=25600,operands=tensor}` | 30 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=65536,operands=tensor}` | 24 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact); residual_add (chip-emu, exact, fp32-exact) |
| `layernorm{channels=256,layout=channels_last,tokens=100}` | 19 | 0 | cpu | cpu | - |
| `relu{numel=524288}` | 17 | 0 | cpu | cpu | - |
| `relu{numel=1048576}` | 13 | 0 | cpu | cpu | - |
| `layernorm{channels=256,layout=channels_last,tokens=256}` | 12 | 0 | cpu | cpu | - |
| `relu{numel=262144}` | 11 | 0 | cpu | cpu | - |
| `rmsnorm{channels=32,tokens=8192}` | 11 | 0 | cpu | cpu | - |
| `rmsnorm{channels=32,tokens=32768}` | 7 | 0 | cpu | cpu | - |
| `rmsnorm{channels=64,tokens=8192}` | 7 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=1048576,operands=tensor}` | 6 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=204800,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=524288,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `mul{broadcast=0,numel=80000,operands=scalar}` | 6 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=204800}` | 6 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=8192}` | 6 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=100,rows=800}` | 6 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_partial (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=256,rows=2048}` | 6 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `softmax{dim_last=1,n=256,rows=800}` | 6 | 0 | chip | chip-emu | softmax_exp2_nx8_e4 (chip, approximation, exp2_nx8_e4); softmax_rows_long (chip-emu, exact, fp32-exact) |
| `relu{numel=131072}` | 5 | 0 | cpu | cpu | - |
| `relu{numel=2097152}` | 5 | 0 | cpu | cpu | - |
| `rmsnorm{channels=16,tokens=8192}` | 5 | 0 | cpu | cpu | - |
| `rmsnorm{channels=64,tokens=32768}` | 5 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=2097152,operands=tensor}` | 4 | 0 | cpu | cpu | - |
| `relu{numel=4194304}` | 4 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=32768}` | 4 | 0 | cpu | cpu | - |
| `rmsnorm{channels=16,tokens=32768}` | 4 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=4194304,operands=tensor}` | 3 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=524288,operands=tensor}` | 3 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=16,operands=scalar}` | 2 | 0 | chip+host | chip+host | add_exact (chip+host, exact, exact) |
| `aten{numel=32768,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=65536,schema=aten::flatten.using_ints}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=32768}` | 2 | 0 | cpu | cpu | - |
| `cos{numel=16384}` | 2 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 2 | 0 | cpu | cpu | - |
| `div{broadcast=0,numel=128,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `div{broadcast=1,numel=256,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `div{broadcast=1,numel=32768,operands=tensor}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=256,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `relu{numel=25600}` | 2 | 0 | cpu | cpu | - |
| `sin{numel=16384}` | 2 | 0 | cpu | cpu | - |
| `aten{numel=256,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=64,h=256,k=3,padding=1,stride=2,w=256}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=128,operands=scalar}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `pow{numel=128}` | 1 | 0 | cpu | cpu | - |
| `repeat{numel=25600}` | 1 | 0 | cpu | cpu | - |
| `rmsnorm{channels=128,tokens=16384}` | 1 | 0 | cpu | cpu | - |
| `rmsnorm{channels=256,tokens=16384}` | 1 | 0 | cpu | cpu | - |
| `rmsnorm{channels=32,tokens=16384}` | 1 | 0 | cpu | cpu | - |
| `rmsnorm{channels=64,tokens=16384}` | 1 | 0 | cpu | cpu | - |
| `sigmoid{numel=400}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1,h=512,mode=nearest2d,out_elements=1024,w=512}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1,h=512,mode=nearest2d,out_elements=16384,w=512}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1,h=512,mode=nearest2d,out_elements=256,w=512}` | 1 | 0 | cpu | cpu | - |
| `upsample{channels=1,h=512,mode=nearest2d,out_elements=4096,w=512}` | 1 | 0 | cpu | cpu | - |

