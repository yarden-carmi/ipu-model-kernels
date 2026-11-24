{% set one = cr.one ~ '.L' %}
{% macro gather() %}
    MULT.EE LR0 CR1 0 LR12 {{ one }} {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ one }}
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR12 CR1 0 LR12 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}

    SET LR3 CR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
    INC LR10 128 ; SET LR12 CR0 ;;
batch:
    SET LR5 LR4 ; SET LR6 {{ cr.in0_d2 }} ; SET LR0 CR0 ;;
column:
    SET LR8 LR5 ; SET LR7 {{ cr.in0_d1 }} ;;
tile:
    SET LR1 LR8 ; SUB LR2 LR12 CR1 ; SET LR9 LR7 ;;
    BLT.S LR7 LR10 bound ;;
    SET LR9 LR10 ;;
bound:
    DEC LR9 3 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR9 CR1 last ;;
gather_lane:
    {{ gather() }} ; INC LR2 1 ; ADD LR1 LR1 {{ cr.width }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR2 LR9 gather_lane ;;
last:
    {{ gather() }} ; INC LR2 1 ; ADD LR8 LR1 {{ cr.width }} ; LD.MULT R0 LR3 {{ cr.operand }} ; BLE.S LR7 LR10 tail ;;
    {{ store('CR15.L') }} ;;
    SUB LR7 LR7 LR10 ; INC LR3 1 ; B tile ;;
tail:
    {{ store(cr.tail ~ '.L') }} ;;
    INC LR3 1 ; INC.MODP2 LR0 CR1 7 ; DEC LR6 1 ; BEQ LR6 CR1 next_batch ;;
    BNE LR0 CR0 column ;;
    INC LR5 1 ; B column ;;
next_batch:
    ADD LR4 LR4 {{ cr.batch_stride }} ;;
    BLT.S LR4 {{ cr.input_end }} batch ;;
    HALT ;;
