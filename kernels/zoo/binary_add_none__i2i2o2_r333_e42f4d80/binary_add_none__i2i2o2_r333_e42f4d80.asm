{% macro sum(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.rows }} ;;
    DEC LR2 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% if in0_d2 % 128 == 0 %}
row:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; BGE.S LR1 LR2 done ;;
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B row ;;
{% else %}
group:
    SET LR3 LR14 ; DEC LR3 1 ;;
    {% if in0_d2 > 128 %}
full_row:
    {{ sum(cr.tail ~ '.H') }}
    DEC LR3 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S CR1 LR3 full_row ;;
    {% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; BGE.S LR1 LR2 done ;;
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B group ;;
{% endif %}
done:
    HALT ;;
