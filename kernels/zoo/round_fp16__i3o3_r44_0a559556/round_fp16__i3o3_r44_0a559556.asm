{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro mul(reg, scalar='CR1') %}MULT.VE {{ reg }} {{ scalar }} 0 LR0 {{ ds }} {{ qi }}{% endmacro %}
    SET LR2 {{ cr.ra_half }} ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
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
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.half }} ;;
    {{ mul('LR0') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR2', cr.overflow_limit) }} ; ACC.SUB ; ACTIVATE.QUANTIZE relu6 {{ ds }} {{ qi }} {{ cr.positive }} LR0 ;;
    {{ mul('LR0') }} ; ACC.SUB.FIRST ;;
    {{ mul('LR2', cr.overflow_limit) }} ; ACC.SUB ; ACTIVATE.QUANTIZE relu6 {{ ds }} {{ qi }} {{ cr.negative }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.bias }} ;;
    {# Around 0.75 the FP32 grid is the binary16 subnormal grid (2^-24). #}
    {{ mul('LR2') }} ; ACC.ADD.FIRST ;;
    {{ mul('LR0') }} ; ACC.ADD ;;
    {{ mul('LR2') }} ; ACC.SUB ; LD.MULT R0 LR0 {{ cr.positive }} ;;
    LD.MULT R1 LR0 {{ cr.negative }} ;;
    {{ mul('LR0', cr.overflow_gain) }} ; ACC.ADD ;;
    {{ mul('LR2', cr.overflow_gain) }} ; ACC.SUB ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ mul('LR0', cr.zero_sign_scale) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
