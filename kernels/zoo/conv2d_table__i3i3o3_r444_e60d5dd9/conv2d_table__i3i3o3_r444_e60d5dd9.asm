{# Stage three horizontal shifts for the stride-one, 3x3 dense path. #}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% macro bound(r, n) %}
SET {{ r }} CR0 ;;
{% for off in range(0, n|abs, 255) %}
{% if n > 0 %} INC {{ r }} {{ [255, n-off]|min }} ;;
{% elif n < 0 %} DEC {{ r }} {{ [255, -n-off]|min }} ;; {% endif %}
{% endfor %}
{% endmacro %}
{% macro zeros(name) %}
SET LR13 CR0 ;;
{{ name }}:
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;
INC LR5 1 ; INC LR13 1 ; BLT.S LR13 LR12 {{ name }} ;;
{% endmacro %}
SET LR13 CR0 ;;
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
INC LR13 1 ;;
{% endfor %}
{% if stride == 1 and kw == 3 and padding == 1 and in1_d3 <= 128 and out0_d3 == in1_d3 %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
INC LR2 128 ; INC LR3 192 ; SET LR5 CR0 ;;
INC LR3 192 ; DEC LR5 1 ; SET LR6 CR0 ;;
SET LR9 CR0 ; SET LR15 CR0 ;;
INC LR9 2 ; DEC LR15 1 ;;
{{ bound('LR14', cin - 1) }}
{{ bound('LR11', cin - 1) }}
{{ bound('LR10', in1_d2 - 1) }}
{{ bound('LR12', 2) }}
stage_channel:
{{ zeros('top') }}
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ; SET LR4 LR15 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
{{ bound('LR8', 127) }}
{{ bound('LR9', 128) }}
{{ bound('LR2', 129) }}
stage_y:
LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR1 ; INC LR4 1 ;;
MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ADD LR13 LR5 CR1 ;
ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR13 ;;
LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ;;
{% for k in range(3) %}
MULT.RC.VE {{ ['LR8', 'LR9', 'LR2'][k] }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% endfor %}
INC LR7 1 ; ADD LR4 LR4 LR14 ; BLT.S LR7 LR10 stage_y ;;
{{ bound('LR2', 256) }}
{{ zeros('bottom') }}
INC LR6 1 ; INC LR15 1 ; BLT.S LR6 LR11 stage_channel ;;
{% if groups == 1 and cin > 4 and kh == 3 %}
SET LR6 CR0 ; SET LR10 CR0 ; SET LR4 CR0 ;;
DEC LR4 1 ; DEC LR10 1 ;;
{{ bound('LR9', cout - 1) }}
{{ bound('LR8', cout) }}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro dense(more) %}
ADD LR13 LR15 CR1 ; SET LR14 CR0 ; SET LR1 LR2 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ;;
{% for t in range(9) %}
MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if loop.first %} DEC LR1 128 ; {% else %} INC LR14 1 ; INC LR1 1 ; {% endif %}
{% if more and loop.last %} INC LR11 1 ; LD.MULT R0 LR11 {{ cr.weights }} ; {% endif %}
{% if more and t == 7 %} ADD LR15 LR15 {{ cr.step_plane }} ; {% endif %} ;;
MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if not loop.last %}
INC LR13 1 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; {% if more and t == 7 %} INC LR12 1 ; {% endif %}
{% elif more %}
INC LR11 1 ; LD.MULT R1 LR11 {{ cr.weights }} ; BLT.S LR12 {{ cr.loop_limit }} input_channel ;
{% else %}
ACTIVATE.QUANTIZE generic {{ tail }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR7 1 ; INC LR4 3 ;
{% endif %} ;;
{% endfor %}
{% endmacro %}
output_channel:
SET LR7 CR0 ; LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ; SET LR5 LR6 ;;
LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ; DEC LR5 1 ;;
output_y:
MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; ADD LR11 LR10 CR1 ; LD.MULT R0 LR11 {{ cr.weights }} ; SET LR15 LR4 ;;
MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR11 1 ; LD.MULT R1 LR11 {{ cr.weights }} ; SET LR12 CR1 ;;
input_channel:
{{ dense(true) }}
{{ dense(false) }}
ADD LR5 LR5 LR9 ; BLT.S LR7 {{ cr.out0_d2 }} output_y ;;
SET LR10 LR11 ; INC LR6 1 ;;
SET LR4 CR0 ;;
DEC LR4 1 ; BLT.S LR6 LR8 output_channel ;;
{% endif %}
{% endif %}
HALT ;;
