{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    INC LR2 128 ; SET LR9 CR0 ;;
pixel:
    // Gather two spatial scalars per channel directly into the output row.
    SUB LR3 LR0 CR1 ; SET LR4 LR5 ; SET LR7 LR8 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
channel:
    // AGG sees the new channel index; the branch sees the previous index.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR7 {{ cr.in1 }} ; INC LR3 1 ; BEQ LR3 {{ cr.channel_prev }} store ;;
    {{ add_rhs() }} ; ADD LR4 LR4 {{ cr.stride0 }} ; ADD LR7 LR7 {{ cr.in1_d2 }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; B channel ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR1 1 ; INC LR2 1 ;;
    BEQ LR6 {{ cr.rows }} done ;;
    BNE LR1 {{ cr.packed_limit }} rhs_column ;;
    SET LR1 CR0 ; INC LR5 1 ;;
rhs_column:
    BNE LR2 {{ cr.rhs_limit }} pixel ;;
    SET LR2 CR0 ; INC LR8 1 ; INC LR9 1 ;;
    INC LR2 128 ; BNE LR9 {{ cr.in1_d2 }} pixel ;;
    SET LR9 CR0 ; ADD LR8 LR8 {{ cr.batch_extra }} ; B pixel ;;
done:
    HALT ;;
