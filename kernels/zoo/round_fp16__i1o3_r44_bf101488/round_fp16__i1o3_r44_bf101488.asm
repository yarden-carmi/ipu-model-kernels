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
batch:
    SET LR8 CR0 ;;
channel:
    SET LR9 LR10 ;;
    SET LR11 CR0 ;;
spatial:
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    SET LR12 CR0 ;;
    {{ mul('LR0', 'CR0') }} ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD4 LRD6 7 ;;
    ADDBI LRD6 1 ;;
    INC LR9 1 ;;
    INC LR12 1 ;;
    BLT.S LR12 LR15 gather ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.H {{ qi }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
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
    {{ mul('LR2', cr.overflow_gain) }} ; ACC.SUB ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    {{ mul('LR0', cr.zero_sign_scale) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    INC LR11 1 ;;
    BLT.S LR11 LR14 spatial ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d1 }} channel ;;
    SET LR10 LR9 ;;
    INC LR13 1 ;;
    BLT.S LR13 LR1 batch ;;
    HALT ;;
