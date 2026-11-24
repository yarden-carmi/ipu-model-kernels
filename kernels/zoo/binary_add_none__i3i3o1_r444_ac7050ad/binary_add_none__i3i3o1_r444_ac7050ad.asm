{% macro add_rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; INC LR2 128 ;;
pixel:
    // A packed spatial lane is common to all channels. The two loads feed
    // scalar aggregation directly into that channel's output lane.
    SET LR3 CR0 ; SET LR4 LR5 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
channel:
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ; BEQ LR3 {{ cr.channel_last }} store ;;
    {{ add_rhs() }} ; ADD LR4 LR4 {{ cr.channel_stride }} ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    INC LR3 1 ; B channel ;;
store:
    {{ add_rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.rows }} done ;;
    INC LR1 1 ; INC LR2 1 ; BNE LR1 {{ cr.packed_last }} pixel ;;
    SET LR1 CR0 ; SET LR2 CR0 ; INC LR5 1 ;;
    INC LR2 128 ; B pixel ;;
done:
    HALT ;;
