{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ; INC LR1 1 ;;
    MULT.VE LR5 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    SET LR8 LR1 ; INC LR3 1 ; INC LR6 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR7 CR0 ;;
column:
    SET LR1 LR4 ; SET LR8 LR4 ; SET LR6 CR0 ;;
    BEQ LR6 {{ cr.full_blocks }} tail ;;
block:
    {{ add_row('CR15.L') }}
    BLT.S LR6 {{ cr.full_blocks }} block ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    ADD LR4 LR4 {{ cr.row_step }} ; ADD LR5 LR5 {{ cr.lane_step }} ; INC LR7 1 ;;
    BLT.S LR5 {{ cr.lanes }} no_carry ;;
    SUB LR5 LR5 {{ cr.lanes }} ; INC LR4 1 ;;
no_carry:
    BLT.S LR7 {{ cr.columns }} column ;;
    HALT ;;
