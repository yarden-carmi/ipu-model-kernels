{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR3 1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR5 CR0 ;;
    INC LR5 1 ;;
plane:
    SET LR3 CR0 ;;
row:
    SET LR4 {{ cr.chunks }} ;;
    BEQ LR4 LR5 tail ;;
chunk:
    {{ add_row('CR15.L') }}
    DEC LR4 1 ;;
    BNE LR4 LR5 chunk ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    BLT.S LR3 {{ cr.plane_rows }} row ;;
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;
