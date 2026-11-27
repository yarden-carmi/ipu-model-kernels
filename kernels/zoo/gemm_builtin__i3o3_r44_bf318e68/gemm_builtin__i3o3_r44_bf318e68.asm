{% set p = [4, 128 // in0_d3] | min %}
{% macro row(shift, tag) %}
    SET LR8 CR0 ; SET LR6 {{ cr.n }} ; SET LR10 CR0 ;;
    INC LR10 {{ 128 + shift * in0_d3 }} ; DEC LR8 1 ; SET LR11 CR0 ;;
    INC LR11 {{ shift * in0_d3 }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{{ tag }}_out:
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ; SET LR2 LR5 ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ; ADD LR2 LR2 {{ cr.in_groups }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR4 {{ cr.k }} ;;
{% if k > 1 %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR1 ; DEC LR4 1 ;;
{{ tag }}_k:
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ; ADD LR2 LR2 {{ cr.in_groups }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR4 1 ; BEQ LR4 CR1 {{ tag }}_end ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR1 ; BEQ LR0 CR0 {{ tag }}_k ;;
{{ tag }}_end:
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; DEC LR6 1 ; BNE LR6 CR1 {{ tag }}_out ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; SET LR5 CR0 ; DEC LR3 1 ;;
{% set groups = in0_d2 // p %}
{% if groups %}
    SET LR9 CR0 ;;
    INC LR9 {{ groups }} ;;
group:
{% for j in range(p) %}
    {{ row(j, 'r' ~ j) }}
{% endfor %}
    INC LR5 1 ; DEC LR9 1 ; BNE LR9 CR1 group ;;
{% endif %}
{% for j in range(in0_d2 % p) %}
    {{ row(j, 't' ~ j) }}
{% endfor %}
    HALT ;;
