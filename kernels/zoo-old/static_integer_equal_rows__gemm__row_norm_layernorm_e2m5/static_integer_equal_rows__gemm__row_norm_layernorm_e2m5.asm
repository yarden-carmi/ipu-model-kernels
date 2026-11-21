{% set ke = [s0_vocab, 8] | min %}
{% set nb = s1_n // 128 %}
{% macro store(row, act='identity') %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    ACTIVATE.QUANTIZE {{ act }} CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro pair(row) %}
{{ store(row) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(row+1) }}
{% endmacro %}
{% macro load(row, slot='LR0') %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
{% endmacro %}
{% macro ra(row) %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% endmacro %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{ s0_tokens // 128 }} ;;
    INC LR13 {{ nb }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(ke) %}
{% for boundary in [k, k+1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(boundary) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR11 ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR11 ;;
{% if boundary == k %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR1 ;;
{% endif %}
{% endfor %}
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.x }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 {{ ke }} ;;
    BLT.S LR9 LR12 block ;;
{% for r in range(16) %}
    SET LR{{ r }} CR0 ;;
{% endfor %}
    INC LR3 128 ; INC LR7 1 ;;
norm_row:
    SET LR5 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for b in range(nb) %}
    LD.MULT R0 LR5 {{ cr.x }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.x }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
{% endfor %}
{{ pair(2) }}
{% for dest,elem in [(4,0),(6,1)] %}
{{ ra(2) }}
    INC LR1 1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    SET LR8 CR0 ;;
    INC LR8 {{ elem }} ;;
    SET LR9 CR0 ;;
    INC LR9 {{ 128+elem }} ;;
    MULT.EE LR8 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(dest) }}
{% endfor %}
    LD.MULT R0 LR0 {{ cr.c }} ;;
{{ load(4) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ load(5) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(8) }}
    LD.MULT R0 LR0 {{ cr.c }} ;;
{{ load(6) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ load(7) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ load(8) }}
{{ ra(8) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ ra(9) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R0 LR0 {{ cr.eps }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ store(12,'rsqrt') }}
{{ pair(10) }}
{{ load(12) }}
{{ ra(12) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ pair(14) }}
{% for a,b in [(10,14),(10,15),(11,14),(11,15)] %}
{{ load(a) }}
{{ ra(b) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(16) }}
{{ load(12) }}
{% for a in [16,17] %}
{{ ra(a) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(20) }}
{{ load(12) }}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for a in [20,21] %}
{{ load(a) }}
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ pair(22) }}
    SET LR5 LR2 ; SET LR11 CR0 ;;
{% for b in range(nb) %}
    LD.MULT.CYCLIC LR11 {{ cr.gamma }} LR0 ;;
{% for a in [22,23] %}
{{ ra(a) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(24) }}
    LD.MULT.CYCLIC LR5 {{ cr.x }} LR0 ;;
{% for w in [24,25] %}
{{ ra(w) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% for a in [8,9] %}
{{ load(a,'LR3') }}
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{% endfor %}
    LD.MULT R0 LR11 {{ cr.beta }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR11 1 ;;
{% endfor %}
    INC LR2 {{ nb }} ; INC LR4 1 ;;
    SET LR6 CR0 ;;
    INC LR6 {{ s2_rows - 1 }} ;;
    INC LR6 1 ;;
    BLT.S LR4 LR6 norm_row ;;
    HALT ;;
