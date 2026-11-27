{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro mul(reg, scalar='CR1') %}MULT.VE {{ reg }} {{ scalar }} 0 LR0 {{ ds }} {{ qi }}{% endmacro %}
    SET LR2 CR1 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% for i in range(7) %}    ADD LR2 LR2 LR2 ;;
{% endfor %}
    {{ mul('LR0', 'CR0') }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} {{ cr.bias }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.bias }} ;;
    {{ mul('LR2', 'CR0') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR2') }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} {{ cr.half }} LR0 ;;
    {{ mul('LR2') }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} {{ cr.bias }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.half }} ;;
    LD.MULT R1 LR0 {{ cr.bias }} ;;
    {{ mul('LR0') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR2') }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.bias }} LR0 ;;
row:
    SET LR4 {{ cr.indices }} ; SET LR5 {{ cr.indices }} ;;
    ADDBI LRD4 4 ;;
    SET LR4 {{ cr.indices }} ;;
    SET LR6 LR4 ; SET LR7 LR5 ;;
{% macro gather() %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    {{ mul('LR0') }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    ADDBI LRD4 8 ; ADDBI LRD6 8 ;;
    {{ mul('LR0') }} ; ACC.RESHAPE LRD4 LRD6 0 ;;
    SET LR4 {{ cr.indices }} ; SET LR5 {{ cr.indices }} ;;
    ADDBI LRD4 4 ; ADDBI LRD6 8 ; INC LR8 1 ;;
    SET LR4 {{ cr.indices }} ;;
{% endmacro %}
{% for i in range(8) %}{{ gather() }}{% endfor %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.out0 }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.out0 }} ;;
    LD.MULT R1 LR0 {{ cr.half }} ;;
    {{ mul('LR0') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR2', cr.overflow_limit) }} ; ACC.SUB ; ACTIVATE.QUANTIZE relu6 {{ ds }} {{ qi }} {{ cr.positive }} LR0 ;;
    {{ mul('LR0') }} ; ACC.SUB.FIRST ;;
    {{ mul('LR2', cr.overflow_limit) }} ; ACC.SUB ; ACTIVATE.QUANTIZE relu6 {{ ds }} {{ qi }} {{ cr.negative }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.bias }} ;;
    {{ mul('LR2') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR0') }} ; ACC.ADD ;;
    {{ mul('LR2') }} ; ACC.SUB ; LD.MULT R0 LR0 {{ cr.positive }} ;;
    LD.MULT R1 LR0 {{ cr.negative }} ;;
    {{ mul('LR0', cr.overflow_gain) }} ; ACC.ADD ;;
    {{ mul('LR2', cr.overflow_gain) }} ; ACC.SUB ; LD.MULT R0 LR1 {{ cr.out0 }} ;;
    {{ mul('LR0', cr.zero_sign_scale) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
