{% macro add_row(ds) %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR2 {{ cr.operand }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR2 1 ; INC LR3 1
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; SET LR6 {{ cr.planes }} ;;
plane:
    SET LR2 CR0 ; SET LR4 CR0 ;;
column:
    SET LR5 CR0 ; BEQ LR7 CR0 tail ;;
full:
    {{ add_row('CR15.L') }} ; BLT.S LR5 LR7 full ;;
tail:
    {{ add_row(cr.tail ~ '.L') }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.in0_d3 }} column ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 plane ;;
    HALT ;;
