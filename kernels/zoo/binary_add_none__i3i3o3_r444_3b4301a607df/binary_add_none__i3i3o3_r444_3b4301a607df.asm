{% if out0_d3 <= 128 %}
    SET LR5 CR0 ; SET LR6 {{ cr.neg_one }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.last }} final ;;
loop:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR5 {{ cr.bound }} loop ;;
final:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; HALT ;;
{% else %}
{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    INC LR2 128 ;;
outer:
    SET LR3 {{ cr.blocks }} ;;
block:
    DEC LR3 1 ;;
    BEQ LR3 CR0 last ;;
    {{ add_row('CR15.L') }}
    BEQ LR0 CR0 block ;;
last:
    {{ add_row(cr.tail ~ '.L') }}
    BLT.S LR1 {{ cr.rows }} outer ;;
    HALT ;;
{% endif %}
