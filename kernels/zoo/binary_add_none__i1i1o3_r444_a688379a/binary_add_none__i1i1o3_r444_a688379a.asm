// LR1/LR2 are the channel indices in R0/R1. LR3 walks input
// spatial rows, LR4 walks output rows, and LR5 selects the output lane.
{% macro rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR5 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR6 CR0 ; SET LR7 {{ cr.spatial }} ; SET LR2 CR0 ;;
    INC LR2 128 ;;
channel:
    SET LR3 LR6 ;;
row:
    SET LR5 CR0 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
pixel:
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.ds_pair }}.L ; LD.MULT R1 LR3 {{ cr.in1 }} ;;
    {{ rhs() }} ; INC LR3 1 ; BEQ LR5 {{ cr.last_x }} store ;;
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR5 1 ; B pixel ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; BNE LR3 LR7 next_row ;;
    INC LR4 1 ;;
    BEQ LR4 {{ cr.output_rows }} done ;;
    INC LR1 1 ; INC LR2 1 ; BNE LR1 {{ cr.last_channel }} channel ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR6 LR7 ;;
    INC LR2 128 ; ADD LR7 LR7 {{ cr.spatial }} ; B channel ;;
next_row:
    INC LR4 1 ; B row ;;
done:
    HALT ;;
