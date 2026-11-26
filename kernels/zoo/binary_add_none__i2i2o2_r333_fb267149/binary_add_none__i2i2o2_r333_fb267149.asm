// The view's flat storage index is i + d0*j + d0*d1*k.
// LR4:LR5 tracks its origin for k=0; LR6:LR7 tracks the current element.
// LR1:LR2 is the packed destination row and lane.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR4 CR0 ; SET LR5 LR3 ; SET LR14 {{ cr.out0_d1 }} ;;
channel:
    BLT.S LR5 LR13 origin ;;
    INC LR4 1 ; DEC LR5 128 ;;
origin:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR15 {{ cr.out0_d2 }} ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar }}.L ; DEC LR15 1 ; ADD LR6 LR6 {{ cr.stride_rows }} ;;
{% if stride_lanes != 0 %}
    ADD LR7 LR7 {{ cr.stride_lanes }} ; INC LR2 1 ;;
    BLT.S LR7 LR13 positioned ;;
    INC LR6 1 ; DEC LR7 128 ;;
positioned:
{% else %}
    INC LR2 1 ;;
{% endif %}
    BNE LR2 LR13 next_element ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
next_element:
    BNE LR15 CR0 gather ;;
    DEC LR14 1 ; ADD LR5 LR5 {{ cr.out0_d0 }} ;;
    BNE LR14 CR0 channel ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.out0_d0 }} batch ;;
    HALT ;;
