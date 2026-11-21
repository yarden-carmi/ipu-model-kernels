{# The frozen graph uses in1; in0 is handed through the boundary but is not an operand. #}
{% set wp = in1_d3 + 2 %}
{% set wo = out0_d3 %}
{% set ic = (in1_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set cwl = cin - 128 * (ic - 1) %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro step(r, n) %}
{% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro stage(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro pair(src, first=false, advance=false, branch=none) %}
 MULT.RC.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1{% if advance %} ; INC LR9 1{% endif %} ;;
 MULT.RC.VE LR1 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1{% if branch %} ; BLT.S LR9 LR15 {{ branch }}{% endif %} ;;
{% endmacro %}
{% macro block(tag, lim) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 DEC LR9 1 ; INC LR15 {{ lim - 2 }} ;;
{{ tag }}:
{% for c in range(8) %}
 {{ pair('LR9', advance=true, branch=tag if c == 7 else none) }}
{% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR9 CR0 ; SET LR14 CR0 ;;
 DEC LR9 1 ;;
zfill:
 {{ stage('CR0') }} ; INC LR14 1 ;;
 BLT.S LR14 {{ cr.padrows }} zfill ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
 DEC LR10 1 ; SET LR15 CR0 ;;
 {{ step('LR15', in1_d2) }}
 {{ step('LR9', (wp + 1) * ic - 1) }}
cy:
 SET LR11 CR0 ;;
cx:
 LD.MULT R0 LR10 {{ cr.in1 }} ; INC LR10 1 ; INC LR11 1 ;;
 {{ stage('CR1') }} ;;
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
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; DEC LR8 {{ oc }} ; SET LR4 LR5 ;;
oy:
 SET LR6 CR0 ;;
pix:
 {{ pair('CR1', first=true) }}
{% macro tap(t) %}
{% if ic > 1 %}
 SET LR12 CR0 ;;
 INC LR12 {{ ic - 1 }} ;;
full{{ t }}:
 {{ block('fc' ~ t, 128) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 full{{ t }} ;;
{% endif %}
 {{ block('lc' ~ t, cwl) }}
{% if t % 3 == 2 and t < 8 %}
 {{ step('LR4', (wp - 3) * ic) }}
{% endif %}
{% endmacro %}
{% for t in range(9) %}
 {{ tap(t) }}
{% endfor %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; SET LR13 LR14 ;;
 INC LR6 1 ; INC LR5 {{ stride * ic }} ;;
 SET LR4 LR5 ; BLT.S LR6 LR10 pix ;;
 INC LR7 1 ;;
 {{ step('LR5', stride * (wp - wo) * ic) }}
 SET LR4 LR5 ; BLT.S LR7 LR11 oy ;;
 INC LR2 1 ; ADD LR14 LR14 {{ cr.orows }} ;;
 BLT.S LR2 {{ cr.oc }} ochunk ;;
 HALT ;;
