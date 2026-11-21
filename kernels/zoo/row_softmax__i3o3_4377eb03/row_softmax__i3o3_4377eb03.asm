{% set K = (n + 127) // 128 %}
{% set cr = dict(qf=cr.qf_in0, qf_out0=cr.qf_out0, in0=cr.in0, out0=cr.out0, tmp=cr.tmp, exps=cr.exps, K=cr.K, M=cr.M) %}
{% macro sum_terms(count) %}
{% for term in range(count) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{% if term == 0 %}.FIRST{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro small_constant(power, numerator, row) %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for term in range(power) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB{% if term == 0 %}.FIRST{% endif %} ;;
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ sum_terms(numerator) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro scaled(first, ds) %}
{% for row in [8,9,10,11] %}
    SET LR5 CR0 ;;
    INC LR5 {{ row }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if (row == 11) != (not first) %}SUB{% else %}ADD{% endif %}{% if first and row == 8 %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if row == 11 %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ sum_terms(16) }}
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ sum_terms(23) }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{{ small_constant(12,21,9) }}
{{ small_constant(18,18,10) }}
{{ small_constant(25,19,11) }}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    INC LR5 126 ;;
epsilon_loop:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    DEC LR5 1 ;;
    BNE LR5 CR0 epsilon_loop ;;
    INC LR1 5 ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
row_loop:
    SET LR4 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for tile in range(K) %}
{% set ds = 'CR14.L' if tile == K - 1 else 'CR15.L' %}
{% if tile > 0 %}
    INC LR4 1 ;;
{% endif %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; {% if tile == 0 %}AGG.MAX.FIRST{% else %}AGG.MAX{% endif %} LR0 {{ ds }} ;;
{% endfor %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% for tile in range(K) %}
{% set ds = 'CR14.L' if tile == K - 1 else 'CR15.L' %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{{ scaled(true, ds) }}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    INC LR5 12 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
    INC LR4 1 ;;
    INC LR3 1 ;;
{% endfor %}
    SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for tile in range(K) %}
{% set ds = 'CR14.L' if tile == K - 1 else 'CR15.L' %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in [3,4] %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% for tile in range(K) %}
{% set ds = 'CR14.L' if tile == K - 1 else 'CR15.L' %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR5 CR0 ;;
    INC LR5 12 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
    MULT.VE LR9 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endfor %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
