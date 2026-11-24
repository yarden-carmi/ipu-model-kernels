{% macro sum_row(ds, last='') %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; {{ last }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 {{ cr.rows }} ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
    DEC LR3 1 ;;
{% if in0_d2 % 128 == 0 %}
row:
    {{ sum_row(cr.tail ~ '.H', 'BEQ LR1 LR3 done') }}
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B row ;;
{% else %}
group:
    SET LR2 LR14 ;;
{% if in0_d2 > 128 %}
full_row:
    {{ sum_row(cr.tail ~ '.H') }}
    INC LR1 1 ; DEC LR2 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S CR1 LR2 full_row ;;
{% endif %}
    {{ sum_row(cr.tail ~ '.L', 'BEQ LR1 LR3 done') }}
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B group ;;
{% endif %}
done:
    HALT ;;
