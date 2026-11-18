{% set K = (n + 127) // 128 %}
{% set cr = dict(qf=cr.qf_in0, qf_out0=cr.qf_out0, in0=cr.in0, out0=cr.out0, tmp=cr.tmp, exps=cr.exps, K=cr.K, M=cr.M) %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(16) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 8 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(23) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(12) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
    INC LR1 3 ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(21) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
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
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR5 CR0 ;;
    INC LR5 9 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    SET LR5 CR0 ;;
    INC LR5 8 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR5 2 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
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
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endfor %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
