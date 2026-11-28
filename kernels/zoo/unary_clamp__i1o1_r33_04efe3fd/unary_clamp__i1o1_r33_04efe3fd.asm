{% macro compute() %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}
{% macro double() %}
    LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR4 ;;
{% endmacro %}
    SET LR2 CR0 ; SET LR3 {{ cr.minus_one }} ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR0 ;;
{% for i in range(5) %}{{ double() }}{% endfor %}
    LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; SET LR4 {{ cr.three }} ; LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR4 3 ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR4 ;;
    SET LR4 {{ cr.two }} ; LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR4 5 ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR4 ;;
    SET LR4 CR0 ; LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR4 8 ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR4 ;;
    SET LR4 {{ cr.six }} ; LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.work }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.work }} ;;
    INC LR4 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.work }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.last_row }} row ;;
    BEQ LR2 CR0 tail ;;
row:
    {{ compute() }} ; INC LR2 1 ; INC LR3 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.penultimate }} row ;;
tail:
    {{ compute() }} ; INC LR3 1 ;;
    HALT ;;
