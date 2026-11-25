{% set gc = cin // groups %}
{% set oc = cout // groups %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro adjust(reg, n) %}
 {% for i in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs-i]|min }} ;;
 {% endfor %}
{% endmacro %}

{# The spatial row lives between two zero rows in the cyclic register. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR5 CR0 ;;
 INC LR1 128 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.zero }} LR2 ;;
 LD.MULT.CYCLIC LR0 {{ cr.zero }} LR0 ; SET LR12 LR1 ;;
 INC LR12 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.zero }} LR12 ;;
 {# Copy only active lanes, ensuring row tails cannot feed horizontal taps. #}
 SET LR11 CR0 ; SET LR10 CR1 ; SET LR14 CR0 ;;
copy_count:
 ADD LR14 LR14 {{ cr.in0_d1 }} ; INC LR2 1 ;;
 BLT.S LR2 {{ cr.in0_d2 }} copy_count ;;
copy_rows:
 LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ cr.ds_in }}.L {{ qi }} {{ cr.zero }} LR10 ;;
 INC LR11 1 ; INC LR10 1 ;;
 BLT.S LR11 LR14 copy_rows ;;
 SET LR2 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
 INC LR2 1 ;;
{% endfor %}
 SET LR6 CR0 ; SET LR9 CR1 ;;
y_loop:
 SET LR8 CR0 ; SET LR14 CR0 ; SET LR3 CR0 ;;
group_loop:
 SET LR7 CR0 ;;
channel_loop:
{% for part in range(3) %}
 LD.MULT R0 LR3 {{ cr.weights }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ; INC LR3 1 ;;
{% endfor %}
 ADD LR4 LR9 LR8 ; SET LR13 CR0 ;;
input_loop:
{% for part in range(3) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; SET LR10 LR6 ; SET LR11 LR4 ; SET LR2 CR0 ;;
 INC LR3 1 ;;
 {{ adjust('LR10', -padding) }}
 {{ adjust('LR11', -padding * cin) }}
 {% for ky in range(kh) %}
 BLT.S LR10 LR0 skip_{{ part }}_{{ ky }} ;;
 BGE.S LR10 {{ cr.in0_d2 }} skip_{{ part }}_{{ ky }} ;;
 LD.MULT.CYCLIC LR11 {{ cr.zero }} LR1 ; SET LR12 LR1 ;;
 {{ adjust('LR12', -padding) }}
 {% for kx in range(kw) %}
 MULT.RC.VE LR12 LR2 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 INC LR2 1 ; INC LR12 1 ;;
 {% endfor %}
 BEQ LR0 LR0 next_{{ part }}_{{ ky }} ;;
skip_{{ part }}_{{ ky }}:
 INC LR2 {{ kw }} ;;
next_{{ part }}_{{ ky }}:
 {% if not loop.last %}
 INC LR10 1 ; ADD LR11 LR11 {{ cr.in0_d1 }} ;;
 {% endif %}
 {% endfor %}
{% endfor %}
{% if gc > 1 %}
 INC LR13 1 ; INC LR4 1 ; SET LR10 CR0 ;;
 {{ adjust('LR10', gc) }}
 BLT.S LR13 LR10 input_loop ;;
{% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 else 'identity' }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ;;
{% if oc > 1 %}
 INC LR7 1 ; SET LR10 CR0 ;;
 {{ adjust('LR10', oc) }}
 BLT.S LR7 LR10 channel_loop ;;
{% endif %}
 INC LR14 1 ;;
 {{ adjust('LR8', gc) }}
 BLT.S LR14 LR15 group_loop ;;
 INC LR6 1 ; ADD LR9 LR9 {{ cr.in0_d1 }} ;;
 BLT.S LR6 {{ cr.out0_d2 }} y_loop ;;
 HALT ;;
