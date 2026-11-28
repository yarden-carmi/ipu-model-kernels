{% macro add_row(ds, decrement=false) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD {% if decrement %}; DEC LR3 1{% endif %} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    INC LR2 128 ;;
outer:
    SET LR3 {{ cr.blocks }} ;;
    DEC LR3 1 ;;
    BEQ LR3 CR0 last ;;
inner:
    {{ add_row('CR15.L', true) }}
    INC LR1 1 ; BNE LR3 CR0 inner ;;
last:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR1 1 ; BLT.S LR1 {{ cr.rows }} outer ;;
    HALT ;;
