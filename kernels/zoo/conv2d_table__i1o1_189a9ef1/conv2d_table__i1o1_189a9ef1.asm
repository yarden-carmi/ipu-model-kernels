{# Process one channel chunk at a time, keeping spatial rows interleaved
   by chunk in both handed tensors. Scratch holds one zero-padded plane. #}
{% set wp = in0_d3 + 2 %}
{% set wo = out0_d3 %}
{% macro step(r, n) %}
{% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro zero() %}
 MULT.VE LR0 CR0 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in0 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ;;
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
 SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR3 1 ;;
chunk:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; DEC LR10 {{ (in0_d1 + 127) // 128 }} ; SET LR11 CR0 ;;
 SET LR12 CR0 ;;
 {{ step('LR11', in0_d3) }}
 {{ step('LR12', in0_d2) }}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 {{ zero_loop('top', wp + 1) }}
copy_y:
 SET LR6 CR0 ;;
copy_x:
 LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ (in0_d1 + 127) // 128 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in0 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; BLT.S LR6 LR11 copy_x ;;
{% for i in range(2) %}
 {{ zero() }}
{% endfor %}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zero_loop('bottom', wp - 1) }}

{% if groups == 1 %}
{# dense: one scalar element (input channel) per weight row; weight row r+1 is loaded while row r multiplies #}
{% macro tap(t) %}
{% if t == 0 %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; MULT.VE LR0 CR0 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD.FIRST ;;
{% else %}
 LD.MULT R0 LR4 {{ cr.pad }} ; {{ 'ADD LR4 LR4 ' ~ cr.w if t % 3 == 0 else 'INC LR4 1' }} ; SUB LR14 LR14 {{ cr.cin }}{{ ' ; INC LR5 ' ~ stride if t == 1 else '' }}{{ ' ; INC LR6 1' if t == 2 else '' }} ;;
{% endif %}
tap{{ t }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; BLT.S LR14 {{ cr.cm2 }} tap{{ t }} ;;
{% endmacro %}
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 DEC LR8 1 ; SET LR13 CR0 ; SET LR14 CR0 ;;
 DEC LR14 1 ;;
 {{ step('LR10', wo) }}
 {{ step('LR11', out0_d2) }}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
dpixel:
 SET LR4 LR5 ;;
 DEC LR4 1 ;;
{% for t in range(9) %}
{{ tap(t) }}
{% endfor %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; SUB LR14 LR14 {{ cr.cin }} ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; SET LR13 CR0 ; ACTIVATE.QUANTIZE generic {{ cr.ds128 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 1 ; BLT.S LR6 LR10 dpixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo)) }}
 BLT.S LR7 LR11 dpixel ;;
 HALT ;;
{% else %}
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
