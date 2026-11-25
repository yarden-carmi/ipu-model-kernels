{% macro rhs() %}
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.planes }} ;;
plane:
    SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ; SET LR8 CR0 ;;
    SET LR9 LR5 ;;
channel:
    // LR9 is the first pixel's row for this channel chunk.
    SET LR4 LR9 ; SUB LR3 LR0 CR1 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
pixel:
    // AGG sees the incremented slot; BEQ tests its previous value.
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ; INC LR3 1 ; BEQ LR3 {{ cr.last_slot_prev }} store ;;
    {{ rhs() }} ; ADD LR4 LR4 {{ cr.chunks }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; B pixel ;;
store:
    {{ rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR8 1 ; INC LR1 1 ;;
    INC LR2 1 ;;
    BEQ LR8 {{ cr.out0_d1 }} next_plane ;;
    BNE LR1 {{ cr.lanes }} channel ;;
    SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ; INC LR9 1 ; B channel ;;
next_plane:
    ADD LR5 LR5 {{ cr.plane_stride }} ; DEC LR7 1 ;;
    BNE LR7 CR0 plane ;;
    HALT ;;
