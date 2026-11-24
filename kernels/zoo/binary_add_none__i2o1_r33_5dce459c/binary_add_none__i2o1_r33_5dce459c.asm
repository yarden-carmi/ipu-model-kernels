{% macro gather() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_ds }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_ds }}.H
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{% endmacro %}

// LR3: batch base, LR7: column chunk, LR6: column lane.
// LR8: logical column, LR9: output lane block, LR4: current input row.
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR15 CR0 ;;
    INC LR15 128 ; B first_batch ;;
column:
    ADD LR4 LR3 LR7 ; SET LR9 CR0 ;;
block:
    SET LR2 CR0 ; SET LR10 LR15 ; LD.MULT R0 LR4 {{ cr.in0 }} ; BNE LR9 {{ cr.last_block }} count_ready ;;
    SET LR10 {{ cr.last_count }} ;;
count_ready:
    DEC LR10 1 ; DEC LR2 1 ;;
    BEQ LR10 CR0 last ;;
    DEC LR10 2 ;;
gather_loop:
    {{ gather() }} ; INC LR2 1 ; ADD LR4 LR4 LR14 ; LD.MULT R0 LR4 {{ cr.in0 }} ; BLT.S LR2 LR10 gather_loop ;;
last:
    {{ gather() }} ; INC LR2 1 ; ADD LR4 LR4 LR14 ; LD.MULT R0 LR5 {{ cr.operand }} ; BEQ LR9 {{ cr.last_block }} tail ;;
    {{ store('CR15.L') }} ; INC LR9 1 ;;
    INC LR5 1 ; B block ;;
tail:
    {{ store(cr.tail_ds ~ '.L') }} ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.total_rows }} done ;;
    INC LR8 1 ; INC LR6 1 ;;
    BEQ LR8 {{ cr.in0_d2 }} batch ;;
    BLT.S LR6 LR15 column ;;
    SET LR6 CR0 ; INC LR7 1 ; B column ;;
batch:
    ADD LR3 LR3 {{ cr.batch_rows }} ;;
first_batch:
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR6 CR0 ; B column ;;
done:
    HALT ;;
