{# Each gather emits two adjacent spatial positions from one packed in1 row.
   Keep separate even/odd slots to advance the even slot during the odd sum.
   Accumulate in FP32 and quantize only when the output row is complete. #}
{% macro sum(lane, qf, slot) %}
    MULT.EE {{ lane }} CR1 0 LR0 {{ cr.active }}.H {{ qf }}.L ; AGG.SUM {{ slot }} {{ cr.active }}.H
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.second }} ;;
    INC LR5 128 ; ADD LR12 LR1 {{ cr.plane }} ;;
channel:
    SET LR7 LR1 ; SET LR9 LR2 ;;
output_row:
    SET LR8 CR0 ; SET LR10 CR0 ; SET LR11 {{ cr.out0_d3 }} ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.EE LR4 CR0 0 LR0 {{ cr.active }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR9 {{ cr.in1 }} ; INC LR10 1 ;;
spatial_pair:
    {{ sum('LR4', cr.qf_in0, 'LR8') }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    {{ sum('LR5', cr.qf_in1, 'LR8') }} ;;
    {{ sum('LR4', cr.qf_in0, 'LR10') }} ; INC LR7 1 ; INC LR9 1 ; DEC LR11 1 ;;
    {{ sum('LR6', cr.qf_in1, 'LR10') }} ; INC LR8 2 ; BEQ LR11 CR0 store ;;
    INC LR10 2 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    LD.MULT R1 LR9 {{ cr.in1 }} ; B spatial_pair ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; BLT.S LR7 LR12 output_row ;;
    INC LR4 1 ; INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR4 {{ cr.out0_d1 }} channel ;;
    ADD LR1 LR1 {{ cr.plane }} ; ADD LR2 LR2 {{ cr.packed_plane }} ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
