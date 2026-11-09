# state-spaces/mamba-130m-hf

- domain: llm, family: mamba, size: 130M, params at full depth: 129.1M
- canonical: state-spaces/mamba-130m-hf
- depth scaling: `{"_scales_from": [1, 1], "n_layer": [24, 2], "num_hidden_layers": [24, 2], "scales": {"backbone.layers": 12.0}}`

## prefill

| layer | calls | MACs/call | best placement | exact placement | implementations |
|---|---:|---:|---|---|---|
| `linear{bias=0,k=768,m=256,n=3072}` | 24 | 603,979,776 | cpu | cpu | - |
| `linear{bias=0,k=768,m=256,n=50280}` | 1 | 9,885,450,240 | cpu | cpu | - |
| `linear{bias=0,k=1536,m=256,n=768}` | 24 | 301,989,888 | cpu | cpu | - |
| `linear{bias=0,k=1536,m=256,n=80}` | 24 | 31,457,280 | cpu | cpu | - |
| `bmm{b=1,k=48,m=1536,n=256}` | 24 | 18,874,368 | cpu | cpu | - |
| `bmm{b=1,k=16,m=1536,n=1}` | 6144 | 24,576 | cpu | cpu | - |
| `add{broadcast=0,numel=24576,operands=tensor}` | 6144 | 0 | chip-emu | chip-emu | residual_add (chip-emu, exact, fp32-exact) |
| `mul{broadcast=0,numel=24576,operands=tensor}` | 6144 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=6291456,operands=tensor}` | 72 | 0 | cpu | cpu | - |
| `silu{numel=393216}` | 48 | 0 | chip | cpu | silu_exp2_recip (chip, approximation, exp2_recip) |
| `rmsnorm{channels=768,tokens=256}` | 25 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=196608,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=0,numel=393216,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `add{broadcast=1,numel=393216,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `aten{numel=397824,schema=aten::conv1d}` | 24 | 0 | cpu | cpu | - |
| `concat{numel=393216}` | 24 | 0 | cpu | cpu | - |
| `exp{numel=24576}` | 24 | 0 | cpu | cpu | - |
| `exp{numel=6291456}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=0,numel=393216,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `mul{broadcast=1,numel=393216,operands=tensor}` | 24 | 0 | cpu | cpu | - |
| `neg{numel=24576}` | 24 | 0 | cpu | cpu | - |
| `softplus{numel=393216}` | 24 | 0 | cpu | cpu | - |
| `embedding{dim=768,tokens=256,vocab=50280}` | 1 | 0 | cpu | cpu | - |

