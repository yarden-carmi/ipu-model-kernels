{# The frozen graph consumes in1 only; in0 keeps its producer's layout. #}
{% set ic = (in1_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set wp = in1_d3 + 2 %}
{% macro inc(reg, amount) %}
{% for i in range(0, amount, 255) %}
 INC {{ reg }} {{ [255, amount-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro pair(scalar, first=false, advance=false, branch='') %}
 MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1{% if advance %} ; INC LR9 1{% endif %} ;;
 MULT.RC.VE LR1 {{ scalar }} 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1{% if branch %} ; BLT.S LR9 LR15 {{ branch }}{% endif %} ;;
{% endmacro %}
{% macro channel_block(n, label) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 DEC LR9 1{% if n >= 8 %} ; INC LR15 {{ n - n % 8 - 2 }}{% endif %} ;;
{% if n >= 8 %}
{{ label }}:
{% for j in range(8) %}
 {{ pair('LR9', advance=true, branch=label if j == 7 and n >= 16 else '') }}
{% endfor %}
{% endif %}
{% for j in range(n % 8) %}
 {{ pair('LR9', advance=true) }}
{% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}

{# Initialize the spatial halo and then overwrite the interior. #}
 SET LR9 CR0 ; SET LR14 CR0 ;;
 DEC LR9 1 ;;
zfill:
 MULT.VE LR0 CR0 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR14 1 ;;
 BLT.S LR14 {{ cr.padrows }} zfill ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
 DEC LR10 1 ; SET LR15 CR0 ; SET LR14 CR0 ;;
 {{ inc('LR15', in1_d2) }}
 {{ inc('LR14', in1_d3 * ic) }}
 {{ inc('LR9', (wp + 1) * ic - 1) }}
cy:
 SET LR11 CR0 ;;
cx:
 LD.MULT R0 LR10 {{ cr.in1 }} ; INC LR10 1 ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds128 }}.L {{ cr.qf_in1 }}.L {{ cr.pad }} LR9 ; INC LR9 1 ; BLT.S LR11 LR14 cx ;;
 INC LR12 1 ; INC LR9 {{ 2 * ic }} ;;
 BLT.S LR12 LR15 cy ;;

 SET LR10 CR0 ; SET LR11 CR0 ; SET LR2 CR0 ;;
 SET LR14 CR0 ;;
 {{ inc('LR10', out0_d3) }}
 {{ inc('LR11', out0_d2) }}
ochunk:
 SET LR13 LR14 ; SET LR5 CR0 ; SET LR7 CR0 ;;
 DEC LR13 1 ; DEC LR5 1 ; SET LR8 LR2 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; DEC LR8 {{ oc }} ; SET LR4 LR5 ;;
oy:
 SET LR6 CR0 ;;
pix:
 {{ pair('CR1', first=true) }}
{% for t in range(9) %}
{% if ic > 1 %}
 SET LR12 CR0 ;;
 INC LR12 {{ ic - 1 }} ;;
full{{ t }}:
 {{ channel_block(128, 'fci' ~ t) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 full{{ t }} ;;
{% endif %}
 {{ channel_block(cin - 128 * (ic - 1), 'tci' ~ t) }}
{% if t in [2, 5] %}
 {{ inc('LR4', (wp - 3) * ic) }}
{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 }} {{ cr.ds128 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; SET LR13 LR14 ;;
 INC LR6 1 ; INC LR5 {{ stride * ic }} ;;
 SET LR4 LR5 ; BLT.S LR6 LR10 pix ;;
 INC LR7 1 ;;
 {{ inc('LR5', stride * (wp - out0_d3) * ic) }}
 SET LR4 LR5 ; BLT.S LR7 LR11 oy ;;
 INC LR2 1 ; ADD LR14 LR14 {{ cr.orows }} ;;
 BLT.S LR2 {{ cr.oc }} ochunk ;;
 HALT ;;
