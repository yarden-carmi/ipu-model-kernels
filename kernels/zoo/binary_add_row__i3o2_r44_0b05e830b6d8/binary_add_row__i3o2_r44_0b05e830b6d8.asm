{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_operand }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
batch:
    SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
column:
    SET LR5 LR7 ; SET LR8 CR0 ;;
plane:
    ADD LR4 LR5 CR0 ; SUB LR3 LR0 CR1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
gather:
    // The branch compares the old slot; the accumulator uses the incremented slot.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.operand }} ; INC LR3 1 ; BEQ LR3 {{ cr.last_slot_prev }} store ;;
    {{ add_rhs() }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; B gather ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR8 1 ; ADD LR5 LR5 {{ cr.in0_d2 }} ;;
    BNE LR8 {{ cr.out0_d1 }} plane ;;
    BEQ LR6 {{ cr.out_rows }} done ;;
    INC LR1 1 ; INC LR2 1 ;;
    BNE LR1 {{ cr.out0_d3 }} column ;;
    SET LR7 LR5 ; B batch ;;
done:
    HALT ;;
