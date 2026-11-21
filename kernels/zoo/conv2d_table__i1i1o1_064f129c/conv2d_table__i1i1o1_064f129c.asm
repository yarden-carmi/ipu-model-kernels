{# Process one channel chunk at a time, keeping spatial rows interleaved
   by chunk in both handed tensors. Scratch holds one zero-padded plane. #}
{% set wp = in1_d3 + 2 %}
{% set wo = out0_d3 %}
{% macro step(r, n) %}
{% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro zero() %}
 MULT.VE LR0 CR0 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
{% endmacro %}
{% macro zero_loop(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count) }}
{{ label }}:
 {{ zero() }}
 INC LR14 1 ;;
 BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}
{% macro pair(src, op, first=false) %}
 {{ op }} LR0 {{ src }} 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {{ op }} LR1 {{ src }} 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
{% if groups == 1 %}
{# dense conv (groups == 1): the whole zero padded input (all channel chunks) in scratch; per output pixel and
   output chunk: bias rows, then for each tap and input channel one weight row (hi, plus lo for tiny cin) times the
   input scalar R0[ci]. Weight rows stream through the two R_CYCLIC slots, one row per word. #}
{% set ic = (in1_d1 + 127) // 128 %}
{% set ocn = (out0_d1 + 127) // 128 %}
{% set rep = 2 %}
{% set cwl = cin - 128 * (ic - 1) %}
{% set wp = in1_d3 + 2 %}
{% set wo = out0_d3 %}
{% macro ciwords(n, label=none) %}
{% for c in range(n) %}{% for r in range(rep) %}{% set j = c * rep + r %}
 MULT.RC.VE {{ 'LR0' if j % 2 == 0 else 'LR1' }} LR9 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} {{ 'LR1' if j % 2 == 0 else 'LR0' }} ; INC LR13 1{% if r == 0 %} ; INC LR9 1{% endif %}{% if label and j == n * rep - 1 %} ; BLT.S LR9 LR15 {{ label }}{% endif %} ;;
{% endfor %}{% endfor %}
{% endmacro %}
{% macro block(tag, lim, loop) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 DEC LR9 1 ; INC LR15 {{ lim - 2 }} ;;
{% if loop %}
{{ tag }}:
{{ ciwords(8, tag) }}
{% else %}
{{ ciwords(lim) }}
{% endif %}
{% endmacro %}
 SET LR9 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 DEC LR9 1 ;;
zfill:
 MULT.VE LR0 CR0 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR14 1 ;;
 BLT.S LR14 {{ cr.padrows }} zfill ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
 DEC LR10 1 ; SET LR15 CR0 ;;
{{ step('LR15', in1_d2) }}
{{ step('LR9', (wp + 1) * ic - 1) }}
cy:
 SET LR11 CR0 ;;
cx:
 LD.MULT R0 LR10 {{ cr.in1 }} ; INC LR10 1 ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
 BLT.S LR11 {{ cr.wic }} cx ;;
 INC LR12 1 ;;
{{ step('LR9', 2 * ic) }}
 BLT.S LR12 LR15 cy ;;
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR2 CR0 ;;
{{ step('LR10', wo) }}
{{ step('LR11', out0_d2) }}
 SET LR14 CR0 ;;
ochunk:
 SET LR13 LR14 ; SET LR5 CR0 ; SET LR7 CR0 ;;
 DEC LR13 1 ; DEC LR5 1 ; SET LR8 LR2 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; DEC LR8 {{ ocn }} ; SET LR4 LR5 ;;
oy:
 SET LR6 CR0 ;;
pix:
 MULT.RC.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% for t in range(9) %}
{% if ic > 1 %}
 SET LR12 CR0 ;;
 INC LR12 {{ ic - 1 }} ;;
f{{ t }}:
{{ block('fc' ~ t, 128, true) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 f{{ t }} ;;
{% endif %}
{{ block('lc' ~ t, cwl, cin > 8) }}
{% if t % 3 == 2 and t < 8 %}
{{ step('LR4', (wp - 3) * ic) }}
{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE generic {{ cr.ds128 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 {{ ocn }} ; SET LR13 LR14 ;;
 INC LR6 1 ; INC LR5 {{ stride * ic }} ;;
 SET LR4 LR5 ; BLT.S LR6 LR10 pix ;;
 INC LR7 1 ;;
{{ step('LR5', (stride * wp - wo * stride) * ic) }}
 SET LR4 LR5 ; BLT.S LR7 LR11 oy ;;
 INC LR2 1 ; ADD LR14 LR14 {{ cr.orows }} ;;
 BLT.S LR2 {{ cr.oc }} ochunk ;;
 HALT ;;
{% else %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR3 1 ;;
chunk:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; DEC LR10 {{ (in1_d1 + 127) // 128 }} ; SET LR11 CR0 ;;
 SET LR12 CR0 ;;
 {{ step('LR11', in1_d3) }}
 {{ step('LR12', in1_d2) }}
 LD.MULT R0 LR2 {{ cr.in1 }} ;;
 {{ zero_loop('top', wp + 1) }}
copy_y:
 SET LR6 CR0 ;;
copy_x:
 LD.MULT R0 LR10 {{ cr.in1 }} ; INC LR6 1 ; INC LR10 {{ (in1_d1 + 127) // 128 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; BLT.S LR6 LR11 copy_x ;;
{% for i in range(2) %}
 {{ zero() }}
{% endfor %}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zero_loop('bottom', wp - 1) }}

 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR8 {{ (out0_d1 + 127) // 128 }} ; SET LR11 CR0 ; SET LR12 CR0 ;;
 {{ step('LR11', wo) }}
 {{ step('LR12', out0_d2) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ;;
 DEC LR4 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% for t in range(9) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {{ pair('R0', 'MULT.RC.VV') }}
{% if t == 2 or t == 5 %}
 {{ step('LR4', wp - 3) }}
{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 }} {{ cr.ds128 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 {{ (out0_d1 + 127) // 128 }} ; INC LR5 {{ stride }} ; INC LR6 1 ;;
 BLT.S LR6 LR11 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo)) }}
 BLT.S LR7 LR12 pixel ;;
 INC LR2 1 ; INC LR3 20 ; SET LR15 {{ cr.oc }} ;;
 BLT.S LR2 LR15 chunk ;;
 HALT ;;
{% endif %}
