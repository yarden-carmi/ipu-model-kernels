{# Byte-quantized phase rows. FP32 widening keeps each integer dot exact. #}
{% set full = cr.ds_out ~ '.H' %}
{% set dst = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qb = cr.qf_weight ~ '.L' %}
{% set qc = cr.qf_coeff ~ '.L' %}
{% macro address(reg, n) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ n }} ;;
{% endmacro %}
{% macro cyclic(n) %}
{{ address('LR9', n) }}
    LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
{% endmacro %}
{% macro split() %}
{{ address('LR9', 7) }}
{% for i in range(3) %}
    ACTIVATE.QUANTIZE identity {{ dst }} {{ qb }} {{ cr.tmp }} LR9 ;;
{% if not loop.last %}
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qb }} ; ACC.SUB ; INC LR9 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}

site:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{{ address('LR9', 10) }}
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; AGG.MAX LR0 {{ full }} ;;
{{ address('LR7', 3) }}
    LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qc }} ; AGG.MAX LR0 {{ full }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qb }} {{ cr.tmp }} LR0 ;;
    SET LR9 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR9 {{ cr.coeff }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qc }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;
{{ address('LR9', 2) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;

# Refine the reciprocal as a sum of four separately stored components.
{{ cyclic(1) }}
{% for i in range(1, 4) %}
    LD.MULT R0 LR0 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qc }} ; ACC.ADD.FIRST ;;
{{ address('LR9', 2) }}
{% for j in range(i) %}
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ; INC LR9 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;
# Residual goes to RC slot zero for the correction multiply.
    LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
{{ address('LR7', 2) }}
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.tmp }} LR9 ;;
{{ cyclic(1) }}
{% endfor %}

    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{{ address('LR9', 2) }}
{% for i in range(4) %}
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ; INC LR9 1 ;;
{% endfor %}
# The FP32 binade around 1.5*2^23 has integer spacing and ties-to-even.
    SET LR7 LR9 ;;
{{ address('LR9', 2) }}
    LD.MULT R0 LR9 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qc }} ; ACC.ADD ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qc }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ qb }} {{ cr.tmp }} LR7 ;;

    SET LR4 LR3 ; SET LR5 CR0 ; SET LR6 CR0 ;;
{{ address('LR8', 7) }}
phase:
{{ cyclic(6) }}
    SET LR7 CR0 ;;
dot:
    LD.MULT R0 LR6 {{ cr.weight }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qb }} ; AGG.SUM.FIRST LR7 {{ full }} ; INC LR6 1 ;;
    INC LR7 1 ;;
    BLT.S LR7 LR14 dot ;;
{{ split() }}

# Multiply the split dots by the split phase scales (which include 1/127).
{% for i in range(3) %}
{{ cyclic(7 + i) }}
    SET LR7 LR8 ;;
{% for j in range(3) %}
    LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qc }} ; ACC.ADD{{ '.FIRST' if i == 0 and j == 0 else '' }} ; INC LR7 1 ;;
{% endfor %}
{% endfor %}
{{ split() }}

    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
{{ address('LR9', 7) }}
{% for i in range(3) %}
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qb }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ; INC LR9 1 ;;
{% endfor %}
{{ address('LR7', 4) }}
{% for i in range(3) %}
    LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qc }} ; ACC.ADD ; INC LR7 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ dst }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR5 1 ; INC LR8 3 ;;
    BLT.S LR5 LR15 phase ;;
    SET LR5 CR0 ; ADD LR4 LR4 LR10 ; BLT.S LR6 LR13 phase ;;

    ADD LR3 LR3 LR15 ; INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 LR11 next_site ;;
    ADD LR3 LR3 LR12 ; SET LR2 CR0 ;;
next_site:
    BLT.S LR1 {{ cr.sites }} site ;;
    HALT ;;
