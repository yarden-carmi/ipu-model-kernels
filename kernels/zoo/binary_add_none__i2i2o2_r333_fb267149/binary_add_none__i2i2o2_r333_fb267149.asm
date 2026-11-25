// The view maps (a,b,c) to the flat input index a + A*b + A*B*c.
// LR3:LR4 is its row/lane address, LR5:LR6 the address at c=0,
// and LR7:LR13 the address at b=c=0.
    INC LR11 128 ;;
row:
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR2 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.single }}.L ; INC LR9 1 ;;
    INC LR2 1 ; BEQ LR9 {{ cr.out0_d2 }} next_b ;;
    ADD LR3 LR3 {{ cr.step_rows }} ;;
{% if (out0_d0 * out0_d1) % 128 %}
    ADD LR4 LR4 LR14 ;;
    BLT.S LR4 LR11 lane_done ;;
    DEC LR4 128 ; INC LR3 1 ;;
{% endif %}
lane_done:
    BLT.S LR2 LR11 gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;

next_b:
    SET LR9 CR0 ; INC LR8 1 ;;
    BEQ LR8 {{ cr.out0_d1 }} next_a ;;
    ADD LR5 LR5 LR15 ; ADD LR6 LR6 LR12 ;;
    BLT.S LR6 LR11 reset_c ;;
    DEC LR6 128 ; INC LR5 1 ;;
reset_c:
    SET LR3 LR5 ; SET LR4 LR6 ; B lane_done ;;

next_a:
    SET LR8 CR0 ; INC LR13 1 ;;
    BLT.S LR13 LR11 reset_b ;;
    DEC LR13 128 ; INC LR7 1 ;;
reset_b:
    SET LR5 LR7 ; SET LR6 LR13 ; B reset_c ;;
