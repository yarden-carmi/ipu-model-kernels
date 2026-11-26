{% set w = (in0_d2 + 127) // 128 %}
{% set step = out0_d0 * out0_d1 %}
{% set row_step = (step // in0_d2) * w %}
{% set col_step = step % in0_d2 %}
{% macro gather1() %}
    MULT.EE LR9 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.tail }}.H
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
row:
    SET LR4 LR12 ; SET LR5 LR13 ; ADD LR8 LR10 LR11 ;;
    SET LR3 {{ cr.out0_d2 }} ; SET LR2 CR0 ;;
element:
    SET LR6 LR4 ; SET LR7 LR5 ;;
lane_check:
    {% if in0_d2 > 128 %}
    SET LR0 CR0 ;;
    INC LR0 128 ;;
    BLT.S LR7 LR0 lane_ready ;;
    DEC LR7 128 ; INC LR6 1 ; B lane_check ;;
    {% endif %}
lane_ready:
    SET LR0 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail }}.H ; LD.MULT R0 LR8 {{ cr.in1 }} ;;
    BEQ LR3 CR1 last ;;
    INC LR0 127 ;;
    BEQ LR2 LR0 full ;;
    SET LR0 CR0 ;;
    {{ gather1() }} ; B advance ;;
full:
    SET LR0 CR0 ;;
    {{ gather1() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; SET LR2 CR0 ; B advance_no_slot ;;
last:
    SET LR0 CR0 ;;
    {{ gather1() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    INC LR14 1 ; INC LR9 1 ; INC LR13 {{ in0_d0 }} ;;
normalize_start:
    BLT.S LR13 {{ cr.in0_d2 }} start_ready ;;
    SUB LR13 LR13 {{ cr.in0_d2 }} ; INC LR12 {{ w }} ; B normalize_start ;;
start_ready:
    BNE LR14 {{ cr.out0_d1 }} same_batch ;;
    SET LR14 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
    ADD LR10 LR10 {{ cr.batch_stride }} ; INC LR15 1 ;;
    SET LR12 CR0 ; SET LR13 LR15 ; B normalize_start ;;
same_batch:
    SET LR0 CR0 ;;
    INC LR0 128 ;;
    BLT.S LR9 LR0 row ;;
    SET LR9 CR0 ; INC LR11 1 ; B row ;;
advance:
    INC LR2 1 ;;
advance_no_slot:
    DEC LR3 1 ; ADD LR8 LR8 {{ cr.blocks }} ; INC LR4 {{ row_step }} ;;
    INC LR5 {{ col_step }} ;;
    BLT.S LR5 {{ cr.in0_d2 }} element ;;
    SUB LR5 LR5 {{ cr.in0_d2 }} ; INC LR4 {{ w }} ; B element ;;
done:
    HALT ;;
