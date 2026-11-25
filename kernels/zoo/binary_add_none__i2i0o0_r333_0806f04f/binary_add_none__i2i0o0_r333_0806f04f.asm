// Output row (j,k) contains the d0 lanes. The view maps that row
// to a contiguous window at flat offset d0*(j + d1*k) in packed in0.
// LR5:LR6 is the (row,lane) start for this j; LR2:LR3 is the cursor.
    INC LR8 128 ;;
outer:
    SET LR2 LR5 ; SET LR3 LR6 ; SET LR4 CR0 ;;
inner:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% if 128 % out0_d0 != 0 %}
    BGE.S {{ cr.last_lane }} LR3 ready ; ADD LR9 LR2 CR1 ;;
    LD.MULT R1 LR9 {{ cr.in0 }} ;;
ready:
{% endif %}
    MULT.VE LR3 CR1 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR4 1 ;;
    BEQ LR4 {{ cr.out0_d2 }} next_outer ; ADD LR2 LR2 {{ cr.step_row }} ; ADD LR3 LR3 {{ cr.step_lane }} ;;
    BLT.S LR3 LR8 inner ;;
    INC LR2 1 ; DEC LR3 128 ; B inner ;;
next_outer:
    INC LR7 1 ; ADD LR6 LR6 {{ cr.out0_d0 }} ;;
    BEQ LR7 {{ cr.out0_d1 }} finish ;;
    BLT.S LR6 LR8 outer ;;
    INC LR5 1 ; DEC LR6 128 ; B outer ;;
finish:
    HALT ;;
