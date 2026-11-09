# densenet121.tv_in1k

- domain: vision-cnn, family: densenet, size: 8M, params at full depth: 8.0M
- canonical: densenet121.tv_in1k
- depth scaling: `{"_scales_from": [0, 0], "scales": {}}`

## forward

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `conv2d{bias=0,cin=128,cout=32,dilation=1,groups=1,h=56,kh=3,kw=3,out_elements=100352,padding=1,stride=1,w=56}` | 6 | 115,605,504 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=32,dilation=1,groups=1,h=28,kh=3,kw=3,out_elements=25088,padding=1,stride=1,w=28}` | 12 | 28,901,376 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=32,dilation=1,groups=1,h=14,kh=3,kw=3,out_elements=6272,padding=1,stride=1,w=14}` | 24 | 7,225,344 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=3,cout=64,dilation=1,groups=1,h=224,kh=7,kw=7,out_elements=802816,padding=3,stride=2,w=224}` | 1 | 118,013,952 | cpu | cpu | - |
| `conv2d{bias=0,cin=1024,cout=512,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=14}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=256,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=200704,padding=0,stride=1,w=28}` | 1 | 102,760,448 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=224,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 89,915,392 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 77,070,336 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 64,225,280 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 51,380,224 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=480,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 48,168,960 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=448,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 44,957,696 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=416,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 41,746,432 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 38,535,168 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=96,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 38,535,168 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=352,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 35,323,904 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 32,112,640 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=32,dilation=1,groups=1,h=7,kh=3,kw=3,out_elements=1568,padding=1,stride=1,w=7}` | 16 | 1,806,336 | chip-emu | chip-emu | conv_universal (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=288,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 28,901,376 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 25,690,112 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=64,cout=128,dilation=1,groups=1,h=56,kh=1,kw=1,out_elements=401408,padding=0,stride=1,w=56}` | 1 | 25,690,112 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=992,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 24,887,296 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 24,084,480 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=928,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 23,281,664 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=224,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 22,478,848 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=896,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 22,478,848 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=864,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 21,676,032 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=832,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 20,873,216 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=800,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 20,070,400 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=192,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 19,267,584 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=768,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 19,267,584 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=736,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 18,464,768 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=704,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 17,661,952 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 16,859,136 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=160,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 16,056,320 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=640,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 16,056,320 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=608,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 15,253,504 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=576,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 14,450,688 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=544,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 13,647,872 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=128,cout=128,dilation=1,groups=1,h=28,kh=1,kw=1,out_elements=100352,padding=0,stride=1,w=28}` | 1 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 12,845,056 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=480,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 12,042,240 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=448,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 11,239,424 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=416,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 10,436,608 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=384,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 9,633,792 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=352,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 8,830,976 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=320,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 8,028,160 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=288,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 7,225,344 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=256,cout=128,dilation=1,groups=1,h=14,kh=1,kw=1,out_elements=25088,padding=0,stride=1,w=14}` | 1 | 6,422,528 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=992,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 6,221,824 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=960,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 6,021,120 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=928,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 5,820,416 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=896,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 5,619,712 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=864,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 5,419,008 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=832,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 5,218,304 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=800,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 5,017,600 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=768,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 4,816,896 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=736,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 4,616,192 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=704,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 4,415,488 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=672,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 4,214,784 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=640,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 4,014,080 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=608,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 3,813,376 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=576,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 3,612,672 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=544,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 3,411,968 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `conv2d{bias=0,cin=512,cout=128,dilation=1,groups=1,h=7,kh=1,kw=1,out_elements=6272,padding=0,stride=1,w=7}` | 1 | 3,211,264 | chip-emu | chip-emu | pointwise_conv_unified (chip-emu, exact, fp32-exact) |
| `linear{bias=1,k=1024,m=1,n=1000}` | 1 | 1,024,000 | cpu | cpu | - |
| `batchnorm{channels=128,hw=196}` | 24 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=49}` | 16 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=784}` | 13 | 0 | cpu | cpu | - |
| `batchnorm{channels=128,hw=3136}` | 7 | 0 | cpu | cpu | - |
| `concat{numel=200704}` | 3 | 0 | cpu | cpu | - |
| `concat{numel=100352}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=125440}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=150528}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=175616}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=301056}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=401408}` | 2 | 0 | cpu | cpu | - |
| `concat{numel=50176}` | 2 | 0 | cpu | cpu | - |
| `adaptive_avgpool2d{channels=1024,h=7,out=1,w=7}` | 1 | 0 | cpu | cpu | - |
| `aten{numel=1024,schema=aten::flatten.using_ints}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=128,h=56,k=2,padding=0,stride=2,w=56}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=256,h=28,k=2,padding=0,stride=2,w=28}` | 1 | 0 | cpu | cpu | - |
| `avgpool2d{channels=512,h=14,k=2,padding=0,stride=2,w=14}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=1024,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=1024,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=160,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=192,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=224,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=224,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=256,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=288,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=288,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=320,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=352,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=352,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=384,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=416,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=416,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=448,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=448,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=480,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=480,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=512,hw=784}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=544,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=544,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=576,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=576,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=608,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=608,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=12544}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=64,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=640,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=640,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=672,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=704,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=704,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=736,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=736,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=768,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=768,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=800,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=800,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=832,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=832,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=864,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=864,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=896,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=896,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=928,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=928,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=96,hw=3136}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=960,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=960,hw=49}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=992,hw=196}` | 1 | 0 | cpu | cpu | - |
| `batchnorm{channels=992,hw=49}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=106624}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=112896}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=119168}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=131712}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=137984}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=144256}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=156800}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=163072}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=169344}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=181888}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=188160}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=194432}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=225792}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=250880}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=25088}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=26656}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=275968}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=28224}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=29792}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=31360}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=326144}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32928}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=34496}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=351232}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=36064}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=376320}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=37632}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=39200}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=40768}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=42336}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=43904}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=45472}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=47040}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=48608}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=501760}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=56448}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=602112}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=62720}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=68992}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=702464}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=75264}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=802816}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=81536}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=87808}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=94080}` | 1 | 0 | cpu | cpu | - |
| `maxpool2d{channels=64,h=112,k=3,padding=1,stride=2,w=112}` | 1 | 0 | cpu | cpu | - |

