{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    INC LR2 128 ; SET LR9 CR0 ;;
row:
    // LR5 is the batch's input base; LR8 is the spatial offset of this row.
    ADD LR4 LR5 LR8 ; SUB LR3 LR0 CR1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
column:
    // The accumulator sees the incremented slot, while BEQ sees the old slot.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ; INC LR3 1 ; BEQ LR3 {{ cr.width_prev }} store ;;
    {{ add_rhs() }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; B column ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; ADD LR8 LR8 {{ cr.out0_d3 }} ; INC LR9 1 ;;
    BEQ LR6 {{ cr.rows }} done ;;
    BNE LR9 {{ cr.out0_d2 }} row ;;
    SET LR9 CR0 ; SET LR8 CR0 ; INC LR1 1 ;;
    INC LR2 1 ;;
    BNE LR1 {{ cr.out0_d1 }} row ;;
    SET LR1 CR0 ; SET LR2 CR0 ; ADD LR5 LR5 {{ cr.plane }} ;;
    INC LR2 128 ; B row ;;
done:
    HALT ;;
