{% set ix = (in0_d3 + 127) // 128 %}
{% set pair = out0_d3 == 64 and out0_d2 % 2 == 0 %}
{% set pack = 2 if pair else 1 %}
{% set full = cr.full ~ '.L' %}
{% set valid = cr.valid ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'gelu', 'sigmoid', 'tanh', 'hardswish'] else act_out0 %}
{% macro constant(reg, n) %}
SET {{ reg }} CR0 ;;
{% for i in range(0,n,255) %}
INC {{ reg }} {{ [255,n-i]|min }} ;;
{% endfor %}
{% endmacro %}

{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
INC LR0 1 ;;
{% endfor %}
SET LR0 CR0 ;;
{{ constant('LR1',128) }}
{{ constant('LR2',256) }}
{{ constant('LR3',384) }}
{{ constant('LR9',in0_d2 * ix) }}
{{ constant('LR14',2) }}
MULT.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.windows }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.windows }} {{ 'LR2' if ix == 1 else 'LR3' }} ;;
{{ constant('LR3', cin) }}
SET LR4 CR1 ;;

{% macro trim(slot, dest) %}
MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.input_tail }}.L {{ qi }} {{ cr.windows }} LR14 ; DEC LR14 1 ;;
LD.MULT.CYCLIC LR14 {{ cr.windows }} {{ dest }} ;;
INC LR14 1 ;;
{% endmacro %}

{# LR7 is the signed source-row offset within the channel plane. #}
{% macro load_row(tag) %}
BLT.S LR7 CR0 zero_{{ tag }} ;;
BGE.S LR7 LR9 zero_{{ tag }} ; ADD LR8 LR5 LR7 ;;
LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR1 ;;
{% if ix == 2 %} LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR2 ; INC LR8 1 ;; {% endif %}
{% if in0_d3 % 128 and not pair %}
{{ trim('LR1' if ix == 1 else 'LR2', 'LR1' if ix == 1 else 'LR2') }}
{% endif %}
BEQ LR0 CR0 loaded_{{ tag }} ;;
zero_{{ tag }}:
LD.MULT.CYCLIC LR0 {{ cr.windows }} LR1 ;;
{% if ix == 2 %} LD.MULT.CYCLIC LR0 {{ cr.windows }} LR2 ;; {% endif %}
loaded_{{ tag }}:
{% endmacro %}

{% macro stage_tap(x) %}
{% if pair and in0_d3 % 128 and x == 2 %}
{# Trim both source rows before starting the packed accumulator. #}
{{ load_row('a' ~ x) }}
{{ constant('LR15',384) }}
{{ trim('LR1','LR15') }}
INC LR7 {{ stride * ix }} ;;
{{ load_row('b' ~ x) }}
{{ trim('LR1','LR1') }}
ADD LR15 LR11 LR2 ;;
MULT.RC.VE LR15 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 {{ 'on off' if stride == 2 else 'off on' }} LR0 ;;
MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 {{ 'on off' if stride == 2 else 'off on' }} LR14 ;
ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.windows }} LR4 ; INC LR4 1 ; DEC LR7 {{ stride * ix }} ;;
{% else %}
{% if pair %}
{{ load_row('a' ~ x) }}
{% endif %}
MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ;
{% if stride == 2 %} ACC.STRIDE 64 on off LR0 ; {% elif pair %} ACC.STRIDE 64 off on LR0 ; {% else %} ACC.ADD.FIRST ; {% endif %}
{% if pair %} INC LR7 {{ stride * ix }} ;
{% elif ix == 1 %} ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.windows }} LR4 ; INC LR4 1 ;
{% else %} ADD LR15 LR11 LR1 ; {% endif %} ;;
{% if pair %}
{{ load_row('b' ~ x) }}
MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 {{ 'on off' if stride == 2 else 'off on' }} LR14 ;
ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.windows }} LR4 ; INC LR4 1 ; DEC LR7 {{ stride * ix }} ;;
{% elif ix == 2 %}
MULT.RC.VE LR15 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR14 ;
ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.windows }} LR4 ; INC LR4 1 ;;
{% endif %}
{% endif %}
{% endmacro %}

stage_channel:
SET LR6 CR0 ; SET LR13 CR0 ;;
DEC LR13 {{ ix }} ;;
stage_y:
SET LR7 LR13 ; SET LR10 CR0 ;;
INC LR10 3 ;;
stage_ky:
{% if not pair %} {{ load_row('single') }} {% endif %}
SET LR11 LR1 ;;
DEC LR11 1 ;;
{% for x in range(3) %}
{{ stage_tap(x) }}
{% if not loop.last %} INC LR11 1 ;; {% endif %}
{% endfor %}
INC LR7 {{ ix }} ; DEC LR10 1 ;;
BNE LR10 CR0 stage_ky ;;
INC LR13 {{ pack * stride * ix }} ; INC LR6 1 ;;
BLT.S LR6 {{ cr.yb }} stage_y ;;
ADD LR5 LR5 LR9 ; INC LR12 1 ;;
BLT.S LR12 LR3 stage_channel ;;

{# Windows are [input channel, output row block, tap]. #}
SET LR1 CR1 ; SET LR5 CR0 ; SET LR6 CR0 ;;
DEC LR5 1 ; DEC LR6 1 ;;
{{ constant('LR8',128) }}
{{ constant('LR12',256) }}
{{ constant('LR13',384) }}
{{ constant('LR15',cout) }}
new_group:
{{ constant('LR14',cout // groups) }}
out_channel:
LD.MULT.CYCLIC LR6 {{ cr.weights }} LR12 ; INC LR6 1 ; SET LR2 CR0 ;;
LD.MULT.CYCLIC LR6 {{ cr.weights }} LR13 ; INC LR6 1 ; SET LR3 LR1 ;;
out_y:
MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD.FIRST ; SET LR4 LR3 ; SET LR7 LR6 ;;
MULT.RC.VE LR13 CR1 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ;;
input_channel:
LD.MULT R0 LR7 {{ cr.weights }} ; INC LR7 1 ; SET LR9 CR0 ;;
LD.MULT R1 LR7 {{ cr.weights }} ; INC LR7 1 ; SET LR10 LR8 ; DEC LR9 1 ;;
DEC LR10 1 ;;
LD.MULT.CYCLIC LR4 {{ cr.windows }} LR0 ; INC LR4 1 ;;
{% for t in range(9) %}
MULT.RC.VE LR0 LR9 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;;
MULT.RC.VE LR0 LR10 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ; INC LR10 1 ;
{% if not loop.last %} LD.MULT.CYCLIC LR4 {{ cr.windows }} LR0 ; INC LR4 1 ; {% endif %} ;;
{% endfor %}
DEC LR4 9 ; INC LR11 1 ;;
ADD LR4 LR4 {{ cr.plane }} ; BLT.S LR11 {{ cr.gc }} input_channel ;;
ACTIVATE.QUANTIZE {{ act }} {{ valid }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR3 9 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.yb }} out_y ;;
SET LR6 LR7 ; DEC LR15 1 ; DEC LR14 1 ;;
BEQ LR15 CR0 finished ;;
BNE LR14 CR0 out_channel ;;
SUB LR1 LR4 {{ cr.plane }} ;;
INC LR1 9 ; BEQ LR0 CR0 new_group ;;
finished:
HALT ;;
