{% macro store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR1 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
    LD.MULT R0 LR0 {{ cr.in1 }} ;;
    # Generate a unit scalar for the finite cap without a constant tensor.
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR2 ;;
    # Move the small denominator out of the reciprocal's subnormal path.
    MULT.EE LR0 {{ cr.two }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    MULT.EE LR0 {{ cr.two }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    LD.MULT R1 LR2 {{ cr.s0 }} ;;
    SET LR8 CR1 ;;
    INC LR8 1 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    # Cap positive overflow before the store so it contributes to the row scale.
    MULT.EE LR3 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ;;
    LD.MULT.CYCLIC LR8 {{ cr.s0 }} LR0 ;;
    MULT.EE LR3 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    BEQ LR2 {{ cr.chunks }} tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; INC LR2 1 ;;
    B row ;;
tail:
    {{ store(cr.tail) }}
    INC LR1 1 ; SET LR2 CR1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
