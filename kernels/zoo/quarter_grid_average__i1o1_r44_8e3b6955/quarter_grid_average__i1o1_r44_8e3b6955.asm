{# Accumulate the first window as a vector, then write only the second
   window's channels into the upper packed lanes. #}
{% macro window(second) %}
    SET LR8 LR5 ;;
{% for y in range(4) %}
    SET LR6 LR8 ;;
{% for x in range(4) %}
{% if not second %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR9 {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR9 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if y == 0 and x == 0 else '' }} ;;
{% else %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR11 CR0 ; SET LR12 {{ 'LR14' if second else 'CR0' }} ;;
    MULT.VE LR11 {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR9 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if y == 0 and x == 0 else '' }} LR12 {{ cr.single }}.L ; BEQ LR14 CR1 next_{{ second }}_{{ y }}_{{ x }} ;;
lane_{{ second }}_{{ y }}_{{ x }}:
    MULT.VE LR11 {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR9 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if y == 0 and x == 0 else '' }} LR12 {{ cr.single }}.L ; INC LR11 1 ; INC LR12 1 ; BLT.S LR11 LR13 lane_{{ second }}_{{ y }}_{{ x }} ;;
next_{{ second }}_{{ y }}_{{ x }}:
{% endif %}
{% if x != 3 %}    INC LR6 1 ;;{% endif %}
{% endfor %}
{% if y != 3 %}
    ADD LR8 LR8 {{ cr.w }} ;;
{% endif %}
{% endfor %}
{% endmacro %}

{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR9 CR0 ; SET LR10 CR0 ;;
batch:
    SET LR3 LR1 ; SET LR4 CR0 ;;
out_y:
    SET LR5 LR3 ; SET LR7 CR0 ;;
out_x:
    BNE LR10 CR0 second ;;
    {{ window(false) }}
    SET LR10 CR1 ;;
    BEQ CR0 CR0 advance ;;
second:
    {{ window(true) }}
    {{ store(cr.valid) }}
    SET LR10 CR0 ; INC LR2 1 ;;
advance:
    INC LR5 2 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d3 }} out_x ;;
    ADD LR3 LR3 {{ cr.vertical_step }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.out0_d2 }} out_y ;;
    ADD LR1 LR1 LR15 ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.out0_d0 }} batch ;;
    BEQ LR10 CR0 finish ;;
    {{ store(cr.tail) }}
finish:
    HALT ;;
