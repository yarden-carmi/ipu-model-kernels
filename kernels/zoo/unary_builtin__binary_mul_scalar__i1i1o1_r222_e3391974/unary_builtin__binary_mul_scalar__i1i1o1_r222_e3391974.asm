{% macro store(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
{% macro clip(a,b,dst,neg,reverse=false) %}
{% if reverse %}
    MULT.RC.VE {{ a }} LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    MULT.RC.VE {{ a }} LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
{% endif %}
{% if a == b and not reverse %}
    MULT.RC.VE {{ b }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
{% else %}
    MULT.RC.VE {{ b }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; LD.MULT R1 LR9 {{ cr.s0 }} ;;
{% endif %}
{% if a != b %}
    MULT.EE LR3 {{ cr.base_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    MULT.EE LR3 {{ cr.neg_cap }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ dst }} ; LD.MULT R1 {{ neg }} {{ cr.s0 }} ;;
{% endmacro %}
{% macro reciprocal(scale,pos,neg) %}
    LD.MULT R0 LR0 {{ cr.in1 }} ;;
    MULT.EE LR0 {{ scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
{% if scale == 'CR1' %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_s0 }} {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} ;;
    LD.MULT R0 {{ pos }} {{ cr.s0 }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ neg }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE relu {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} {{ pos }} ;;
{% endmacro %}
{% macro merge(boost,base) %}
    LD.MULT.CYCLIC {{ boost }} {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC {{ base }} {{ cr.s0 }} LR10 ;;
    MULT.RC.VE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 {{ cr.neg_inv }} 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.s0 }} {{ boost }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR1 ;;
    SET LR3 CR0 ; SET LR4 CR1 ; SET LR7 CR1 ;;
    INC LR3 128 ; INC LR7 1 ;;
    SET LR9 CR1 ;;
    INC LR9 2 ;;
    SET LR8 LR9 ; SET LR10 LR3 ;;
    INC LR8 1 ; INC LR10 128 ;;
    SET LR11 LR8 ; SET LR12 LR8 ; SET LR13 LR8 ;;
    INC LR11 1 ; INC LR12 2 ; SET LR14 LR8 ;;
    INC LR13 3 ; INC LR14 4 ;;
    SET LR15 LR10 ;;
    INC LR15 128 ;;
    LD.MULT R0 LR0 {{ cr.in1 }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.full }}.H {{ cr.qf_in0 }}.L {{ cr.s0 }} LR9 ;;
    {{ reciprocal('CR1','LR11','LR12') }}
    {{ reciprocal(cr.factor,'LR0','LR4') }}
    SET LR6 {{ cr.loop }}.L ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR7 ;;
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ; LD.MULT R0 LR11 {{ cr.s0 }} ;;
    ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.s0 }} LR8 ;;
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.s0 }} LR10 ;;
    LD.MULT R1 LR12 {{ cr.s0 }} ;;
    {{ clip('LR15','LR15','LR13','LR12') }}
    {{ clip('LR15','LR15','LR14','LR12',true) }}
    LD.MULT R0 LR0 {{ cr.s0 }} ;;
    LD.MULT R1 LR4 {{ cr.s0 }} ;;
    {{ clip('LR0','LR10','LR7','LR4') }}
    {{ clip('LR10','LR0','LR8','LR4') }}
    {{ merge('LR7','LR13') }}
    {{ merge('LR8','LR14') }}
    LD.MULT.CYCLIC LR7 {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.s0 }} LR10 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
    MULT.RC.VE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
{% if out0_d1 % 128 == 0 %}
    {{ store(cr.full) }}
    INC LR1 1 ;;
    BLT.S LR1 LR6 row ;;
{% else %}
    SET LR6 {{ cr.loop }}.H ;;
    BEQ LR2 LR6 tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; INC LR2 1 ;;
    B row ;;
tail:
    {{ store(cr.tail) }}
    INC LR1 1 ; SET LR2 CR1 ;;
    SET LR6 {{ cr.loop }}.L ;;
    BLT.S LR1 LR6 row ;;
{% endif %}
    HALT ;;
