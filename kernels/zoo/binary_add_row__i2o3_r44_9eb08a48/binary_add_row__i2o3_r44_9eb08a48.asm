{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_operand }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
plane:
    SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
output_row:
    // Select the same d2 lane in the input (bank R0) and the constant (bank R1).
    ADD LR4 LR5 CR0 ; SET LR3 CR0 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
gather:
    // Each successive input row supplies the next d3 lane of the output.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.operand }} ; BEQ LR3 {{ cr.last_slot }} store ;;
    {{ add_rhs() }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    INC LR3 1 ; B gather ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR1 1 ; INC LR2 1 ;;
    BEQ LR6 {{ cr.out_rows }} done ;;
    BNE LR1 {{ cr.out0_d2 }} output_row ;;
    ADD LR5 LR5 {{ cr.out0_d3 }} ; B plane ;;
done:
    HALT ;;
