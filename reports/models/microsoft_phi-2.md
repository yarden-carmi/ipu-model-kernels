# microsoft/phi-2

- domain: llm, family: phi, size: 2.7B, params at full depth: 2779.7M
- canonical: microsoft/phi-2
- depth scaling: `{"_scales_from": [1, 1], "num_hidden_layers": [32, 2], "scales": {"model.layers": 16.0}}`

## decode

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=10240,m=1,n=2560}` | 32 | 26,214,400 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=1,n=10240}` | 32 | 26,214,400 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=1,n=2560}` | 128 | 6,553,600 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=1,n=51200}` | 1 | 131,072,000 | cpu | cpu | - |
| `bmm{b=32,k=257,m=1,n=80}` | 32 | 657,920 | cpu | cpu | - |
| `bmm{b=32,k=80,m=1,n=257}` | 32 | 657,920 | cpu | cpu | - |
| `mul{broadcast=1,numel=1024,operands=tensor}` | 128 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=1024,operands=tensor}` | 64 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=2560,operands=tensor}` | 64 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `concat{numel=1024}` | 64 | 0 | cpu | cpu | - |
| `concat{numel=2560}` | 64 | 0 | cpu | cpu | - |
| `concat{numel=657920}` | 64 | 0 | cpu | cpu | - |
| `neg{numel=512}` | 64 | 0 | cpu | cpu | - |
| `layernorm{channels=2560,layout=channels_last,tokens=1}` | 33 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=8224,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=10240}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=8224,operands=scalar}` | 32 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `softmax{dim_last=1,n=257,rows=32}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=1,operands=scalar}` | 2 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=32,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=257,operands=scalar}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=32}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=32}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2560,tokens=1,vocab=51200}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=16,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=257}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=32}` | 1 | 0 | cpu | cpu | - |

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=1,k=10240,m=256,n=2560}` | 32 | 6,710,886,400 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=256,n=10240}` | 32 | 6,710,886,400 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=256,n=2560}` | 128 | 1,677,721,600 | cpu | cpu | - |
| `linear{bias=1,k=2560,m=256,n=51200}` | 1 | 33,554,432,000 | cpu | cpu | - |
| `bmm{b=32,k=256,m=256,n=80}` | 32 | 167,772,160 | cpu | cpu | - |
| `bmm{b=32,k=80,m=256,n=256}` | 32 | 167,772,160 | cpu | cpu | - |
| `mul{broadcast=1,numel=262144,operands=tensor}` | 128 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `add{broadcast=0,numel=262144,operands=tensor}` | 64 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=655360,operands=tensor}` | 64 | 0 | cpu | cpu | - |
| `concat{numel=262144}` | 64 | 0 | cpu | cpu | - |
| `concat{numel=655360}` | 64 | 0 | cpu | cpu | - |
| `neg{numel=131072}` | 64 | 0 | cpu | cpu | - |
| `layernorm{channels=2560,layout=channels_last,tokens=256}` | 33 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=2097152,operands=tensor}` | 32 | 0 | cpu | cpu | - |
| `gelu_tanh{numel=2621440}` | 32 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=2097152,operands=scalar}` | 32 | 0 | cpu | cpu | - |
| `softmax{dim_last=1,n=256,rows=8192}` | 32 | 0 | chip-emu | chip-emu | softmax_rows_long (chip-emu, exact, fp32-exact) |
| `add{broadcast=0,numel=256,operands=scalar}` | 3 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=8192,operands=scalar}` | 2 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `aten{numel=256,schema=aten::diff}` | 1 | 0 | cpu | cpu | - |
| `concat{numel=8192}` | 1 | 0 | cpu | cpu | - |
| `cos{numel=8192}` | 1 | 0 | cpu | cpu | - |
| `cumsum{numel=256,out=256}` | 1 | 0 | cpu | cpu | - |
| `embedding{dim=2560,tokens=256,vocab=51200}` | 1 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=4096,operands=tensor}` | 1 | 0 | chip+host | chip+host | mul_exact (chip+host, exact, exact) |
| `select_where{numel=65536}` | 1 | 0 | cpu | cpu | - |
| `sin{numel=8192}` | 1 | 0 | cpu | cpu | - |
| `sub{broadcast=0,numel=1,operands=scalar}` | 1 | 0 | cpu | cpu | - |

