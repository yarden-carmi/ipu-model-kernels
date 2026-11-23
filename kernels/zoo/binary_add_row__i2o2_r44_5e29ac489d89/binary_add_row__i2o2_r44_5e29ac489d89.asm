{% macro add_planes(ds, loop_label) %}
    # Reuse each broadcast chunk across all batch/head planes.
    SET LR5 LR3 ;
    LD.MULT R1 LR3 {{ cr.operand }} ;;
{{ loop_label }}:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    SET LR6 LR5 ; ADD LR5 LR5 {{ cr.period }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;
    BLT.S LR5 {{ cr.rows }} {{ loop_label }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
column:
    SET LR4 {{ cr.full }} ;;
    BEQ LR4 CR0 tail ;;
full:
    {{ add_planes('CR15.L', 'full_planes') }}
    DEC LR4 1 ; INC LR3 1 ;;
    BNE LR4 CR0 full ;;
tail:
    {{ add_planes(cr.tail ~ '.L', 'tail_planes') }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.period }} column ;;
    HALT ;;
