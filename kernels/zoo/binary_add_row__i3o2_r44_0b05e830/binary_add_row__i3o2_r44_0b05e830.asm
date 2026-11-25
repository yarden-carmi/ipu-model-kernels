{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_operand }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
batch:
    ADD LR8 LR7 {{ cr.batch_in_rows }} ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
column:
    SET LR5 LR7 ;;
plane:
    // Gather one column of this plane into the output lanes before quantizing.
    ADD LR4 LR5 CR0 ; SUB LR3 LR0 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
gather:
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.operand }} ; INC LR3 1 ; BEQ LR3 {{ cr.last_slot_prev }} store ;;
    {{ add_rhs() }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; B gather ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; ADD LR5 LR5 {{ cr.in0_d2 }} ;;
    BNE LR5 LR8 plane ;;
    INC LR1 1 ; INC LR2 1 ;;
    BNE LR1 {{ cr.in0_d3 }} column ;;
    SET LR7 LR8 ; BNE LR8 {{ cr.in_rows }} batch ;;
    HALT ;;
