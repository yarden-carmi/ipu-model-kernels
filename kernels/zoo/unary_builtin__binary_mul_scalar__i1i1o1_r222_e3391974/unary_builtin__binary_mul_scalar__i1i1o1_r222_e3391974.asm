{% macro store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR1 ;;
    SET LR3 CR0 ; SET LR4 CR1 ; SET LR7 CR1 ;;
    INC LR3 128 ; INC LR7 1 ;;
    SET LR9 CR1 ;;
    INC LR9 2 ;;
    LD.MULT R0 LR0 {{ cr.in1 }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR9 ;;
    # Store reciprocals of the denominator and twice the denominator.
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR4 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    LD.MULT R1 LR4 {{ cr.s0 }} ;;
    # Use the larger reciprocal estimate and apply the denominator sign separately.
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    MULT.EE LR3 {{ cr.neg_one }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE relu {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR4 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE relu {{ cr.scalar }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    LD.MULT R1 LR4 {{ cr.s0 }} ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    LD.MULT R1 LR9 {{ cr.s0 }} ;;
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} LR7 ;;
    LD.MULT R1 LR4 {{ cr.s0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB.FIRST ;;
    BEQ LR2 {{ cr.chunks }} tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; INC LR2 1 ;;
    B row ;;
tail:
    {{ store(cr.tail) }}
    INC LR1 1 ; SET LR2 CR1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
