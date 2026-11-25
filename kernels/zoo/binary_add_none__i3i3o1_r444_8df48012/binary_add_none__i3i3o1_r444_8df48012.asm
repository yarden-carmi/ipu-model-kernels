{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    INC LR2 128 ;;
pixel:
    // LR5 is the channel-zero row; LR1 is the column within that row.
    SUB LR3 LR0 CR1 ; SET LR4 LR5 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
channel:
    // AGG sees the updated channel index; the branch sees its old value.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ; INC LR3 1 ; BEQ LR3 {{ cr.channel_prev }} store ;;
    {{ add_rhs() }} ; ADD LR4 LR4 {{ cr.out0_d2 }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; B channel ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR1 1 ; INC LR2 1 ;;
    BEQ LR6 {{ cr.rows }} done ;;
    BNE LR1 {{ cr.out0_d3 }} pixel ;;
    SET LR1 CR0 ; SET LR2 CR0 ; INC LR7 1 ;;
    INC LR2 128 ; INC LR5 1 ; BNE LR7 {{ cr.out0_d2 }} pixel ;;
    SET LR7 CR0 ; ADD LR5 LR5 {{ cr.batch_skip }} ; B pixel ;;
done:
    HALT ;;
