{% set K = (n + 127) // 128 %}
{% set cr = dict(qf=cr.qf_in0, qf_out0=cr.qf_out0, in0=cr.in0, out0=cr.out0, tmp=cr.tmp, exps=cr.exps, K=cr.K, M=cr.M) %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
{% set ids = namespace(i=0) %}
{% macro repeat_mult(count, op) %}
{% set ids.i = ids.i + 1 %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ op }}.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 {{ count - 1 }} ;;
repeat_{{ ids.i }}:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ op }} ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 repeat_{{ ids.i }} ;;
{% endmacro %}
{% macro split(ds, row, delta) %}
    SET LR5 CR0 ;;
    INC LR5 {{ row }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR5 {{ delta }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
{% endmacro %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ repeat_mult(32, 'ADD') }}
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ repeat_mult(23, 'ADD') }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% macro small_constant(power, num, row) %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ repeat_mult(power, 'SUB') }}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ repeat_mult(num, 'ADD') }}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{{ small_constant(13,21,9) }}
{{ small_constant(19,18,10) }}
{{ small_constant(26,19,11) }}
{{ small_constant(32,23,14) }}
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
{% macro tiles(name) %}
    SET LR7 CR0 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR7 LR8 {{ name }}_tail ;;
{{ name }}_full:
{{ caller('CR15.L', name ~ '_full') }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 {{ name }}_full ;;
{{ name }}_tail:
{{ caller('CR14.L', name ~ '_tail') }}
{% endmacro %}
{% macro maximum(ds, first) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ;;
    INC LR4 1 ;;
{% endmacro %}
row_loop:
    SET LR4 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% if K == 1 %}
{{ maximum('CR14.L', true) }}
{% else %}
{{ maximum('CR15.L', true) }}
    SET LR7 CR1 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR7 LR8 max_tail ;;
max_full:
{{ maximum('CR15.L', false) }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 max_full ;;
max_tail:
{{ maximum('CR14.L', false) }}
{% endif %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds, tile) tiles('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR9 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
{{ split(ds,15,1) }}
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
{% for idx in [8,9,10,11,14] %}
    SET LR5 CR0 ;;
    INC LR5 {{ idx }} ;;
    SET LR10 CR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if idx in [11,14] %}SUB{% else %}ADD{% endif %}{% if idx == 8 %}.FIRST{% endif %} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.{% if idx in [11,14] %}SUB{% else %}ADD{% endif %} ;;
{% endfor %}
    SET LR5 CR0 ;;
    INC LR5 12 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
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
{% endcall %}
    SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% call(ds, tile) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.exps }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endcall %}
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
    SET LR5 CR0 ;;
    INC LR5 7 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
{{ repeat_mult(16,'ADD') }}
    INC LR5 10 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR5 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    INC LR11 128 ;;
    INC LR11 128 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR11 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds, tile) tiles('store') %}
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    INC LR10 128 ;;
    LD.MULT.CYCLIC LR3 {{ cr.exps }} LR10 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    INC LR5 13 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR6 CR0 ;;
    INC LR6 16 ;;
residual_{{ tile }}:
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 residual_{{ tile }} ;;
    INC LR5 2 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
