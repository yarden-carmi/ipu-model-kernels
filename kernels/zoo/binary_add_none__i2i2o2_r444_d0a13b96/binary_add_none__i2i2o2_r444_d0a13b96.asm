{% if out0_d2 <= 128 %}
{% if out0_d0 * out0_d1 * out0_d3 == 1 %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.neg_one }} ; BEQ LR0 CR0 last ;;
{% else %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.neg_one }} ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% endif %}
loop:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR5 1 ; BLT.S LR5 {{ cr.row_bound }} next ;;
    BEQ LR0 CR0 last ;;
next:
    LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR0 CR0 loop ;;
last:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; HALT ;;
{% else %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    INC LR2 128 ;;
outer_loop:
    SET LR3 {{ cr.blocks }} ;;
block_loop:
    DEC LR3 1 ;;
    BEQ LR3 CR0 last_block ;;
    {{ row('CR15.L') }}
    BEQ LR0 CR0 block_loop ;;
last_block:
    {{ row(cr.tail ~ '.L') }}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.outer }} outer_loop ;;
    HALT ;;
{% endif %}
