{% set pack = [out0_d1, [1, 128 // out0_d3] | max] | min %}
{% macro pixel(digit, channel) %}
    SET LR5 LR1 ; SET LR6 {{ cr.in0_d3 }} ; SET LR3 CR0 ;;
{% if channel * out0_d3 %}    INC LR3 {{ channel * out0_d3 }} ;;
{% endif %}    DEC LR3 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR6 1 ;;
    BEQ LR6 CR0 last_{{ channel }}_{{ digit }} ;;
loop_{{ channel }}_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ; INC LR5 1 ; DEC LR6 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BNE LR6 CR1 loop_{{ channel }}_{{ digit }} ;;
last_{{ channel }}_{{ digit }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
    SET LR9 {{ cr.in0_d0 }} ;;
batch:
    SET LR7 {{ cr.in0_d2 }} ;;
height:
    SET LR4 CR0 ; SET LR8 {{ cr.groups }} ;;
    DEC LR4 1 ;;
group:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% for channel in range(pack) %}
{% for digit in range(2) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ pixel(digit, channel) }}
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; DEC LR8 1 ; BNE LR8 CR1 group ;;
    ADD LR1 LR1 {{ cr.in0_d3 }} ; DEC LR7 1 ; BNE LR7 CR1 height ;;
    DEC LR9 1 ; BNE LR9 CR1 batch ;;
    HALT ;;
