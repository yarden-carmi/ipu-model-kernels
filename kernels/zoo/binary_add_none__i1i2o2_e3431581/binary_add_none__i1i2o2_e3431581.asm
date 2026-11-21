{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// in0 groups are in (patch, position-within-patch) storage order;
// in1 and out0 groups are in (position-within-patch, patch) order.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR6 CR0 ;;
position:
    SET LR4 LR6 ; SET LR7 {{ cr.out0_d1 }} ;;
patch:
    SET LR3 {{ cr.blocks }} ;;
chunk:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; DEC LR3 1 ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; BEQ LR3 CR0 last ;;
    {{ store('CR15.L') }}
    INC LR1 1 ; INC LR4 1 ;;
    BEQ LR0 CR0 chunk ;;
last:
    {{ store(cr.tail ~ '.L') }}
    INC LR1 1 ; INC LR4 1 ; DEC LR7 1 ;;
    ADD LR4 LR4 {{ cr.skip }} ; BNE LR7 CR0 patch ;;
    ADD LR6 LR6 {{ cr.blocks }} ; BLT.S LR1 {{ cr.rows }} position ;;
    HALT ;;
